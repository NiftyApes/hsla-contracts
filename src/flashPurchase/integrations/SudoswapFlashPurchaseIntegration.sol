//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../interfaces/flashPurchaseIntegrations/sudoswapFlashPurchaseIntegration/ISudoswapFlashPurchaseIntegration.sol";
import "../../interfaces/sudoswap/ILSSVMPairFactoryLike.sol";
import "../../interfaces/sudoswap/ILSSVMPair.sol";
import "../../interfaces/sudoswap/ILSSVMRouter.sol";
import "../base/FlashPurchaseIntegrationBase.sol";
import "../../FlashPurchase.sol";

/// @notice Integration of Sudoswap to FlashPurchase to allow purchase of NFT with financing
contract SudoswapFlashPurchaseIntegration is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    PausableUpgradeable,
    FlashPurchaseIntegrationBase,
    ISudoswapFlashPurchaseIntegration
{
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @inheritdoc ISudoswapFlashPurchaseIntegration
    address public offersContractAddress;

    /// @inheritdoc ISudoswapFlashPurchaseIntegration
    address public flashPurchaseContractAddress;

    /// @inheritdoc ISudoswapFlashPurchaseIntegration
    address public sudoswapFactoryContractAddress;
    
    /// @inheritdoc ISudoswapFlashPurchaseIntegration
    address public sudoswapRouterContractAddress;

    /// @notice Mutex to selectively enable ETH transfers
    /// @dev    Follows a similar pattern to `Liquidity.sol`
    bool internal _ethTransferable = false;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the marketplace integration contract.
    function initialize(
        address newOffersContractAddress,
        address newFlashPurchaseContractAddress,
        address newSudoswapFactoryContractAddress,
        address newSudoswapRouterContractAddress
    ) public initializer {
        flashPurchaseContractAddress = newFlashPurchaseContractAddress;
        offersContractAddress = newOffersContractAddress;
        sudoswapFactoryContractAddress = newSudoswapFactoryContractAddress;
        sudoswapRouterContractAddress = newSudoswapRouterContractAddress;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }

    /// @inheritdoc ISudoswapFlashPurchaseIntegrationAdmin
    function updateOffersContractAddress(address newOffersContractAddress) external onlyOwner {
        require(address(newOffersContractAddress) != address(0), "00035");
        emit SudoswapFlashPurchaseIntegrationXOffersContractAddressUpdated(
            offersContractAddress,
            newOffersContractAddress
        );
        offersContractAddress = newOffersContractAddress;
    }

    /// @inheritdoc ISudoswapFlashPurchaseIntegrationAdmin
    function updateFlashPurchaseContractAddress(address newFlashPurchaseContractAddress) external onlyOwner {
        require(address(newFlashPurchaseContractAddress) != address(0), "00055");
        emit SudoswapFlashPurchaseIntegrationXFlashPurchaseContractAddressUpdated(
            flashPurchaseContractAddress,
            newFlashPurchaseContractAddress
        );
        flashPurchaseContractAddress = newFlashPurchaseContractAddress;
    }

    /// @inheritdoc ISudoswapFlashPurchaseIntegrationAdmin
    function updateSudoswapFactoryContractAddress(address newSudoswapFactoryContractAddress) external onlyOwner {
        emit SudoswapFactoryContractAddressUpdated(newSudoswapFactoryContractAddress);
        sudoswapFactoryContractAddress = newSudoswapFactoryContractAddress;
    }

    /// @inheritdoc ISudoswapFlashPurchaseIntegrationAdmin
    function updateSudoswapRouterContractAddress(address newSudoswapRouterContractAddress) external onlyOwner {
        emit SudoswapRouterContractAddressUpdated(newSudoswapRouterContractAddress);
        sudoswapRouterContractAddress = newSudoswapRouterContractAddress;
    }

    /// @inheritdoc ISudoswapFlashPurchaseIntegrationAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc ISudoswapFlashPurchaseIntegrationAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc ISudoswapFlashPurchaseIntegration
    function flashPurchaseSudoswap(
        bytes32 offerHash,
        ILSSVMPair lssvmPair,
        uint256[] memory nftIds
    ) external payable nonReentrant {
        Offer memory offer = _fetchOffer(
            offersContractAddress,
            offerHash
        );

        uint256 numOfNfts = nftIds.length;
        if (numOfNfts > 1) {
            require(offer.floorTerm, "00056");
        }
        
        _validateSudoswapPair(offer, lssvmPair);
        uint256 totalConsiderationAmount = _getConsiderationAmount(lssvmPair, numOfNfts);
        // arrange asset amount from borrower side for the purchase
        _arrangeAssetFromBorrower(msg.sender, offer.asset, offer.amount * numOfNfts, totalConsiderationAmount);
        
        
        // call the FlashPurchase to take fund from the lender side
        for (uint256 i; i < numOfNfts;) {
            _ethTransferable = true;
            IFlashPurchase(flashPurchaseContractAddress).borrowFundsForPurchase(
                offerHash,
                nftIds[i],
                address(this),
                msg.sender,
                abi.encode(lssvmPair, offer.asset)
            );
            unchecked {
                ++i;
            }
        }
        
    }

    /// @inheritdoc ISudoswapFlashPurchaseIntegration
    function flashPurchaseSudoswapSignature(
        Offer memory offer,
        bytes memory signature,
        ILSSVMPair lssvmPair,
        uint256[] memory nftIds
    ) external payable nonReentrant {
        uint256 numOfNfts = nftIds.length;
        if (numOfNfts > 1) {
            require(offer.floorTerm, "00056");
        }

        _validateSudoswapPair(offer, lssvmPair);
        uint256 totalConsiderationAmount = _getConsiderationAmount(lssvmPair, numOfNfts);
        _arrangeAssetFromBorrower(msg.sender, offer.asset, offer.amount * numOfNfts, totalConsiderationAmount);

        // call the FlashPurchase to take fund from the lender side
        for (uint256 i; i < numOfNfts;) {
            _ethTransferable = true;
            IFlashPurchase(flashPurchaseContractAddress).borrowSignature(
                offer,
                signature,
                nftIds[i],
                address(this),
                msg.sender,
                abi.encode(lssvmPair, offer.asset)
            );
            unchecked {
                ++i;
            }
        }
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
        (ILSSVMPair lssvmPair, address purchasingAsset) = abi.decode(data, (ILSSVMPair, address));
        uint256 considerationAmount = _getConsiderationAmount(lssvmPair, 1);

        // Purchase the NFT
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = nftId;
        ILSSVMRouter.PairSwapSpecific[] memory pairSwapSpecific = new ILSSVMRouter.PairSwapSpecific[](1);
        pairSwapSpecific[0] = ILSSVMRouter.PairSwapSpecific({pair: lssvmPair, nftIds: nftIds});
        if (purchasingAsset == ETH_ADDRESS) {
            ILSSVMRouter(sudoswapRouterContractAddress).swapETHForSpecificNFTs{value: considerationAmount}(
                pairSwapSpecific,
                payable(address(this)),
                address(this),
                block.timestamp
            );
        } else {
            IERC20Upgradeable asset = IERC20Upgradeable(purchasingAsset);
            uint256 allowance = asset.allowance(address(this), sudoswapRouterContractAddress);
            if (allowance > 0) {
                asset.safeDecreaseAllowance(sudoswapRouterContractAddress, allowance);
            }
            asset.safeIncreaseAllowance(sudoswapRouterContractAddress, considerationAmount);

            ILSSVMRouter(sudoswapRouterContractAddress).swapERC20ForSpecificNFTs(
                pairSwapSpecific,
                considerationAmount,
                address(this),
                block.timestamp
            );
        }

        // approve the flashPurchase contract for the purchased nft
        IERC721Upgradeable(nftContractAddress).approve(flashPurchaseContractAddress, nftId);
        return true;
    }

    function _validateSudoswapPair(
        Offer memory offer,
        ILSSVMPair lssvmPair
    ) internal view {
        // verify pair provided is a valid clone of sudoswap factory pair template
        ILSSVMPairFactoryLike.PairVariant pairVariant = lssvmPair.pairVariant();
        require(ILSSVMPairFactoryLike(sudoswapFactoryContractAddress).isPair(address(lssvmPair), pairVariant), "00050");

        // fetch purchasing asset address
        address purchasingAsset;
        if (pairVariant == ILSSVMPairFactoryLike.PairVariant.ENUMERABLE_ERC20 || pairVariant == ILSSVMPairFactoryLike.PairVariant.MISSING_ENUMERABLE_ERC20) {
            purchasingAsset = address(lssvmPair.token());
        }
        _requireMatchingAsset(offer.asset, purchasingAsset);
    }

    function _getConsiderationAmount(
        ILSSVMPair lssvmPair,
        uint256 numOfNfts
    ) internal view returns (uint256) {
        // calculate consideration amount
        (ILSSVMPair.Error error, , , uint256 considerationAmount, ) = lssvmPair.getBuyNFTQuote(numOfNfts);
        // Require no error
        require(error == ILSSVMPair.Error.OK, "00053");
        return considerationAmount;
    }

    function _requireEthTransferable() internal view {
        require(_ethTransferable, "00043");
    }

    /// @notice This contract needs to accept ETH to acquire enough funds to purchase NFTs
    receive() external payable {
        _requireEthTransferable();
    }
}