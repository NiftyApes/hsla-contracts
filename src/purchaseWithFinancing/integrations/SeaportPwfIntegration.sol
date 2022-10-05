//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../interfaces/niftyapes/purchaseWithFinancing/integrations/SeaportPwfIntegration/ISeaportPwfIntegration.sol";
import "./base/PwfIntegrationBase.sol";
import "../PurchaseWithFinancing.sol";

/// @notice Integration of Seaport to PurchaseWithFinancing to allow purchase of NFT with financing
contract SeaportPwfIntegration is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    PausableUpgradeable,
    PwfIntegrationBase,
    ISeaportPwfIntegration
{   
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @inheritdoc ISeaportPwfIntegration
    address public offersContractAddress;

    /// @inheritdoc ISeaportPwfIntegration
    address public purchaseWithFinancingContractAddress;

    /// @inheritdoc ISeaportPwfIntegration
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
        address newPurchaseWithFinancingContractAddress,
        address newSeaportContractAddress
    ) public initializer {
        purchaseWithFinancingContractAddress = newPurchaseWithFinancingContractAddress;
        offersContractAddress = newOffersContractAddress;
        seaportContractAddress = newSeaportContractAddress;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }

    /// @inheritdoc ISeaportPwfIntegrationAdmin
    function updateOffersContractAddress(address newOffersContractAddress) external onlyOwner {
        require(address(newOffersContractAddress) != address(0), "00035");
        emit SeaportPwfIntegrationXOffersContractAddressUpdated(
            offersContractAddress,
            newOffersContractAddress
        );
        offersContractAddress = newOffersContractAddress;
    }

    /// @inheritdoc ISeaportPwfIntegrationAdmin
    function updatePurchaseWithFinancingContractAddress(address newPurchaseWithFinancingContractAddress) external onlyOwner {
        require(address(newPurchaseWithFinancingContractAddress) != address(0), "00051");
        emit SeaportPwfIntegrationXPurchaseWithFinancingContractAddressUpdated(
            purchaseWithFinancingContractAddress,
            newPurchaseWithFinancingContractAddress
        );
        purchaseWithFinancingContractAddress = newPurchaseWithFinancingContractAddress;
    }

    /// @inheritdoc ISeaportPwfIntegrationAdmin
    function updateSeaportContractAddress(address newSeaportContractAddress) external onlyOwner {
        emit SeaportContractAddressUpdated(newSeaportContractAddress);
        seaportContractAddress = newSeaportContractAddress;
    }

    /// @inheritdoc ISeaportPwfIntegrationAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc ISeaportPwfIntegrationAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc ISeaportPwfIntegration
    function purchaseWithFinancingSeaport(
        bytes32 offerHash,
        bool floorTerm,
        uint256 nftId,
        ISeaport.Order calldata order,
        bytes32 fulfillerConduitKey
    ) external payable nonReentrant {

        Offer memory offer = _fetchOffer(
            offersContractAddress,
            order.parameters.offer[0].token,
            offerHash,
            floorTerm,
            nftId
        );

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

        uint256 considerationAmount = _calculateConsiderationAmount(order);
        // arrange asset amount from borrower side for the purchase
        _arrangeAssetFromBorrower(msg.sender, offer.asset, offer.amount, considerationAmount);
        
        _ethTransferable = true;
        // call the PurchaseWithFinancing to take fund from the lender side
        IPurchaseWithFinancing(purchaseWithFinancingContractAddress).borrow(
            offerHash,
            offer.nftContractAddress,
            nftId,
            floorTerm,
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
        _verifySenderAndInitiator(initiator, purchaseWithFinancingContractAddress);

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

        // approve the purchaseWithFinancing contract for the purchased nft
        IERC721Upgradeable(nftContractAddress).approve(purchaseWithFinancingContractAddress, nftId);
        return true;
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
