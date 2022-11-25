//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../interfaces/flashPurchaseIntegrations/SeaportFlashPurchaseIntegration/ISeaportFlashPurchaseIntegration.sol";
import "../base/FlashPurchaseIntegrationBase.sol";
import "../../FlashPurchase.sol";

/// @notice Integration of Seaport to FlashPurchase to allow purchase of NFT with financing
/// @title SeaportFlashPurchaseIntegration
/// @custom:version 1.0
/// @author captnseagraves (captnseagraves.eth)
/// @custom:contributor zishansami102 (zishansami.eth)
/// @custom:contributor jyturley
contract SeaportFlashPurchaseIntegration is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    PausableUpgradeable,
    FlashPurchaseIntegrationBase,
    ISeaportFlashPurchaseIntegration
{   
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @inheritdoc ISeaportFlashPurchaseIntegration
    address public offersContractAddress;

    /// @inheritdoc ISeaportFlashPurchaseIntegration
    address public flashPurchaseContractAddress;

    /// @inheritdoc ISeaportFlashPurchaseIntegration
    address public seaportContractAddress;

    /// @notice Mutex to selectively enable ETH transfers
    /// @dev    Follows a similar pattern to `Liquidiy.sol`
    bool internal _ethTransferable = false;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the marketplace integration contract.
    function initialize(
        address newOffersContractAddress,
        address newFlashPurchaseContractAddress,
        address newSeaportContractAddress
    ) public initializer {
        flashPurchaseContractAddress = newFlashPurchaseContractAddress;
        offersContractAddress = newOffersContractAddress;
        seaportContractAddress = newSeaportContractAddress;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }

    /// @inheritdoc ISeaportFlashPurchaseIntegrationAdmin
    function updateOffersContractAddress(address newOffersContractAddress) external onlyOwner {
        require(address(newOffersContractAddress) != address(0), "00035");
        emit SeaportFlashPurchaseIntegrationXOffersContractAddressUpdated(
            offersContractAddress,
            newOffersContractAddress
        );
        offersContractAddress = newOffersContractAddress;
    }

    /// @inheritdoc ISeaportFlashPurchaseIntegrationAdmin
    function updateFlashPurchaseContractAddress(address newFlashPurchaseContractAddress) external onlyOwner {
        require(address(newFlashPurchaseContractAddress) != address(0), "00055");
        emit SeaportFlashPurchaseIntegrationXFlashPurchaseContractAddressUpdated(
            flashPurchaseContractAddress,
            newFlashPurchaseContractAddress
        );
        flashPurchaseContractAddress = newFlashPurchaseContractAddress;
    }

    /// @inheritdoc ISeaportFlashPurchaseIntegrationAdmin
    function updateSeaportContractAddress(address newSeaportContractAddress) external onlyOwner {
        emit SeaportContractAddressUpdated(newSeaportContractAddress);
        seaportContractAddress = newSeaportContractAddress;
    }

    /// @inheritdoc ISeaportFlashPurchaseIntegrationAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc ISeaportFlashPurchaseIntegrationAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc ISeaportFlashPurchaseIntegration
    function flashPurchaseSeaport(
        bytes32 offerHash,
        bool floorTerm,
        ISeaport.Order calldata order,
        bytes32 fulfillerConduitKey
    ) external payable nonReentrant {

        Offer memory offer = _fetchOffer(
            offersContractAddress,
            order.parameters.offer[0].token,
            offerHash,
            floorTerm,
            order.parameters.offer[0].identifierOrCriteria
        );

        _validateOrder(order, offer);

        uint256 considerationAmount = _calculateConsiderationAmount(order);
        // arrange asset amount from borrower side for the purchase
        _arrangeAssetFromBorrower(msg.sender, offer.asset, offer.amount, considerationAmount);
        
        _ethTransferable = true;
        // call the FlashPurchase to take fund from the lender side
        IFlashPurchase(flashPurchaseContractAddress).borrowFundsForPurchase(
            offerHash,
            order.parameters.offer[0].identifierOrCriteria,
            address(this),
            msg.sender,
            abi.encode(order, fulfillerConduitKey)
        );
    }

     function flashPurchaseSeaportSignature(
        Offer memory offer,
        bytes memory signature,
        ISeaport.Order calldata order,
        bytes32 fulfillerConduitKey
    ) external payable nonReentrant {
        _validateOrder(order, offer);

        uint256 considerationAmount = _calculateConsiderationAmount(order);
        // arrange asset amount from borrower side for the purchase
        _arrangeAssetFromBorrower(msg.sender, offer.asset, offer.amount, considerationAmount);
        
        _ethTransferable = true;
        // call the FlashPurchase to take fund from the lender side
        IFlashPurchase(flashPurchaseContractAddress).borrowSignature(
            offer,
            signature,
            order.parameters.offer[0].identifierOrCriteria,
            address(this),
            msg.sender,
            abi.encode(order, fulfillerConduitKey)
        );
    }

    function executeOperation(
        address nftContractAddress,
        uint256 nftId,
        address initiator,
        bytes calldata data
    ) external payable override returns (bool) {
        _ethTransferable = false;
        _verifySenderAndInitiator(initiator, flashPurchaseContractAddress);

        // decode data
        (ISeaport.Order memory order, bytes32 fulfillerConduitKey) = abi.decode(data, (ISeaport.Order, bytes32));
        
        uint256 considerationAmount = _calculateConsiderationAmount(order);

        // Purchase NFT
        if (order.parameters.consideration[0].token == address(0)) {
            require(
                ISeaport(seaportContractAddress).fulfillOrder{ value: considerationAmount }(
                    order,
                    fulfillerConduitKey
                ),
                "00048"
            );
        } else {
            IERC20Upgradeable asset = IERC20Upgradeable(order.parameters.consideration[0].token);
            uint256 allowance = asset.allowance(address(this), seaportContractAddress);
            if (allowance > 0) {
                asset.safeDecreaseAllowance(seaportContractAddress, allowance);
            }
            asset.safeIncreaseAllowance(seaportContractAddress, considerationAmount);

            require(
                ISeaport(seaportContractAddress).fulfillOrder(order, fulfillerConduitKey),
                "00048"
            );
        }

        // approve the flashPurchase contract for the purchased nft
        IERC721Upgradeable(nftContractAddress).approve(flashPurchaseContractAddress, nftId);
        return true;
    }

    function _validateOrder(ISeaport.Order memory order, Offer memory offer) internal pure {
        // requireOrderTokenERC721
        require(order.parameters.offer[0].itemType == ISeaport.ItemType.ERC721, "00049");
        // requireOrderTokenAmount
        require(order.parameters.offer[0].startAmount == 1, "00049");
        // requireOrderNotAuction
        require(
            order.parameters.consideration[0].startAmount ==
                order.parameters.consideration[0].endAmount,
            "00049"
        );

         _requireMatchingAsset(offer.asset, order.parameters.consideration[0].token);
    }

    function _calculateConsiderationAmount(ISeaport.Order memory order) internal pure returns(uint256 considerationAmount) {
        for (uint256 i; i < order.parameters.totalOriginalConsiderationItems;) {
            considerationAmount += order.parameters.consideration[i].endAmount;
            unchecked {
                ++i;
            }
        }
    }

    function _requireEthTransferable() internal view {
        require(_ethTransferable, "00043");
    }

    /// @notice This contract needs to accept ETH to acquire enough funds to purchase NFTs
    receive() external payable {
        _requireEthTransferable();
    }
}
