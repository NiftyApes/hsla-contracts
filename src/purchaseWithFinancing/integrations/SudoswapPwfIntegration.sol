//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../interfaces/niftyapes/purchaseWithFinancing/integrations/sudoswapPwfIntegration/ISudoswapPwfIntegration.sol";
import "../../interfaces/sudoswap/ILSSVMPairFactoryLike.sol";
import "../../interfaces/sudoswap/ILSSVMPair.sol";
import "../../interfaces/sudoswap/ILSSVMRouter.sol";
import "./base/PwfIntegrationBase.sol";
import "../PurchaseWithFinancing.sol";

/// @notice Integration of Sudoswap to PurchaseWithFinancing to allow purchase of NFT with financing
contract SudoswapPwfIntegration is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    PausableUpgradeable,
    PwfIntegrationBase,
    ISudoswapPwfIntegration
{
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @inheritdoc ISudoswapPwfIntegration
    address public offersContractAddress;

    /// @inheritdoc ISudoswapPwfIntegration
    address public purchaseWithFinancingContractAddress;

    /// @inheritdoc ISudoswapPwfIntegration
    address public sudoswapFactoryContractAddress;
    
    /// @inheritdoc ISudoswapPwfIntegration
    address public sudoswapRouterContractAddress;

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
        address newSudoswapFactoryContractAddress,
        address newSudoswapRouterContractAddress
    ) public initializer {
        purchaseWithFinancingContractAddress = newPurchaseWithFinancingContractAddress;
        offersContractAddress = newOffersContractAddress;
        sudoswapFactoryContractAddress = newSudoswapFactoryContractAddress;
        sudoswapRouterContractAddress = newSudoswapRouterContractAddress;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }

    /// @inheritdoc ISudoswapPwfIntegrationAdmin
    function updateOffersContractAddress(address newOffersContractAddress) external onlyOwner {
        require(address(newOffersContractAddress) != address(0), "00035");
        emit SudoswapPwfIntegrationXOffersContractAddressUpdated(
            offersContractAddress,
            newOffersContractAddress
        );
        offersContractAddress = newOffersContractAddress;
    }

    /// @inheritdoc ISudoswapPwfIntegrationAdmin
    function updatePurchaseWithFinancingContractAddress(address newPurchaseWithFinancingContractAddress) external onlyOwner {
        require(address(newPurchaseWithFinancingContractAddress) != address(0), "00051");
        emit SudoswapPwfIntegrationXPurchaseWithFinancingContractAddressUpdated(
            purchaseWithFinancingContractAddress,
            newPurchaseWithFinancingContractAddress
        );
        purchaseWithFinancingContractAddress = newPurchaseWithFinancingContractAddress;
    }

    /// @inheritdoc ISudoswapPwfIntegrationAdmin
    function updateSudoswapFactoryContractAddress(address newSudoswapFactoryContractAddress) external onlyOwner {
        emit SudoswapFactoryContractAddressUpdated(newSudoswapFactoryContractAddress);
        sudoswapFactoryContractAddress = newSudoswapFactoryContractAddress;
    }

    /// @inheritdoc ISudoswapPwfIntegrationAdmin
    function updateSudoswapRouterContractAddress(address newSudoswapRouterContractAddress) external onlyOwner {
        emit SudoswapRouterContractAddressUpdated(newSudoswapRouterContractAddress);
        sudoswapRouterContractAddress = newSudoswapRouterContractAddress;
    }

    /// @inheritdoc ISudoswapPwfIntegrationAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc ISudoswapPwfIntegrationAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc ISudoswapPwfIntegration
    function purchaseWithFinancingSudoswap(
        bytes32 offerHash,
        bool floorTerm,
        ILSSVMPair lssvmPair,
        uint256 nftId
    ) external payable nonReentrant {
        // fetch nft contract address
        address nftContractAddress = address(lssvmPair.nft());

        Offer memory offer = _fetchOffer(
            offersContractAddress,
            nftContractAddress,
            offerHash,
            floorTerm,
            nftId
        );

        // verify pair provided is a valid clone of sudoswap factory pair template
        ILSSVMPairFactoryLike.PairVariant pairVariant = lssvmPair.pairVariant();
        require(ILSSVMPairFactoryLike(sudoswapFactoryContractAddress).isPair(address(lssvmPair), pairVariant), "00050");

        // fetch purchasing asset address
        address purchasingAsset;
        if (pairVariant == ILSSVMPairFactoryLike.PairVariant.ENUMERABLE_ERC20 || pairVariant == ILSSVMPairFactoryLike.PairVariant.MISSING_ENUMERABLE_ERC20) {
            purchasingAsset = address(lssvmPair.token());
        }
        _requireMatchingAsset(offer.asset, purchasingAsset);

        // calculate consideration amount
        (ILSSVMPair.Error error, , , uint256 considerationAmount, ) = lssvmPair.getBuyNFTQuote(1);
        // Require no error
        require(error == ILSSVMPair.Error.OK, "00053");
        // arrange asset amount from borrower side for the purchase
        _arrangeAssetFromBorrower(msg.sender, offer.asset, offer.amount, considerationAmount);
        
        _ethTransferable = true;
        // call the PurchaseWithFinancing to take fund from the lender side
        IPurchaseWithFinancing(purchaseWithFinancingContractAddress).borrow(
            offerHash,
            nftContractAddress,
            nftId,
            floorTerm,
            address(this),
            msg.sender,
            abi.encode(lssvmPair, offer.asset, considerationAmount)
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
        (ILSSVMPair lssvmPair, address purchasingAsset, uint256 considerationAmount) = abi.decode(data, (ILSSVMPair, address, uint256));

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

        // approve the purchaseWithFinancing contract for the purchased nft
        IERC721Upgradeable(nftContractAddress).approve(purchaseWithFinancingContractAddress, nftId);
        return true;
    }

    function _requireEthTransferable() internal view {
        require(_ethTransferable, "00043");
    }

    /// @notice This contract needs to accept ETH to acquire enough funds to purchase NFTs
    receive() external payable {
        _requireEthTransferable();
    }
}
