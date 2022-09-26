//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "./interfaces/niftyapes/purchaseWithFinancing/IPurchaseWithFinancing.sol";
import "./interfaces/niftyapes/lending/ILending.sol";
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./interfaces/niftyapes/offers/IOffers.sol";
import "./interfaces/sanctions/SanctionsList.sol";
import "./interfaces/seaport/ISeaport.sol";
import "./interfaces/sudoswap/ILSSVMPairFactoryLike.sol";
import "./interfaces/sudoswap/ILSSVMPair.sol";
import "./interfaces/sudoswap/ILSSVMRouter.sol";

/// @notice Extension of NiftApes lending contract to allow for Seaport purchases
contract NiftyApesPurchaseWithFinancing is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    IPurchaseWithFinancing
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    /// @dev Internal address used for for ETH
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Internal constant address for the Chainalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    /// @inheritdoc IPurchaseWithFinancing
    address public offersContractAddress;

    /// @inheritdoc IPurchaseWithFinancing
    address public liquidityContractAddress;

    /// @inheritdoc IPurchaseWithFinancing
    address public lendingContractAddress;

    /// @inheritdoc IPurchaseWithFinancing
    address public sigLendingContractAddress;

    /// @inheritdoc IPurchaseWithFinancing
    address public seaportContractAddress;

    /// @inheritdoc IPurchaseWithFinancing
    address public sudoswapFactoryContractAddress;

    /// @inheritdoc IPurchaseWithFinancing
    address public sudoswapRouterContractAddress;

    /// @notice Mutex to selectively enable ETH transfers
    /// @dev    Follows a similar pattern to `Liquidiy.sol`
    bool internal _ethTransferable = false;

    /// @dev The status of sanctions checks. Can be set to false if oracle becomes malicious.
    bool internal _sanctionsPause;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the NiftyApes protocol.
    ///         Nifty Apes is intended to be deployed behind a proxy amd thus needs to initialize
    ///         its state outsize of a constructor.
    function initialize(address newSeaportContractAddress, address newSudoswapFactoryContractAddress, address newSudoswapRouterContractAddress) public initializer {
        seaportContractAddress = newSeaportContractAddress;
        sudoswapFactoryContractAddress = newSudoswapFactoryContractAddress;
        sudoswapRouterContractAddress = newSudoswapRouterContractAddress;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function updateLiquidityContractAddress(address newLiquidityContractAddress)
        external
        onlyOwner
    {
        require(address(newLiquidityContractAddress) != address(0), "00035");
        emit PurchaseWithFinancingXLiquidityContractAddressUpdated(
            liquidityContractAddress,
            newLiquidityContractAddress
        );
        liquidityContractAddress = newLiquidityContractAddress;
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function updateOffersContractAddress(address newOffersContractAddress) external onlyOwner {
        require(address(newOffersContractAddress) != address(0), "00035");
        emit PurchaseWithFinancingXOffersContractAddressUpdated(
            offersContractAddress,
            newOffersContractAddress
        );
        offersContractAddress = newOffersContractAddress;
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function updateLendingContractAddress(address newLendingContractAddress) external onlyOwner {
        require(address(newLendingContractAddress) != address(0), "00035");
        emit PurchaseWithFinancingXLendingContractAddressUpdated(
            lendingContractAddress,
            newLendingContractAddress
        );
        lendingContractAddress = newLendingContractAddress;
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function updateSigLendingContractAddress(address newSigLendingContractAddress)
        external
        onlyOwner
    {
        require(address(newSigLendingContractAddress) != address(0), "00035");
        emit PurchaseWithFinancingXSigLendingContractAddressUpdated(
            sigLendingContractAddress,
            newSigLendingContractAddress
        );
        sigLendingContractAddress = newSigLendingContractAddress;
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function updateSeaportContractAddress(address newSeaportContractAddress) external onlyOwner {
        emit SeaportContractAddressUpdated(newSeaportContractAddress);
        seaportContractAddress = newSeaportContractAddress;
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function pauseSanctions() external onlyOwner {
        _sanctionsPause = true;
        emit PurchaseWithFinancingSanctionsPaused();
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function unpauseSanctions() external onlyOwner {
        _sanctionsPause = false;
        emit PurchaseWithFinancingSanctionsUnpaused();
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IPurchaseWithFinancing
    function purchaseWithFinancingSeaport(
        address nftContractAddress,
        bytes32 offerHash,
        bool floorTerm,
        ISeaport.Order calldata order,
        bytes32 fulfillerConduitKey
    ) external payable whenNotPaused nonReentrant {
        // fetch offer
        Offer memory offer = IOffers(offersContractAddress).getOffer(
            nftContractAddress,
            order.parameters.offer[0].identifierOrCriteria,
            offerHash,
            floorTerm
        );

        // remove non-floor offer
        if (!offer.floorTerm) {
            _requireMatchingNftId(offer, order.parameters.offer[0].identifierOrCriteria);
            IOffers(offersContractAddress).removeOffer(
                offer.nftContractAddress,
                order.parameters.offer[0].identifierOrCriteria,
                offerHash,
                floorTerm
            );
        }

        _doPurchaseWithFinancingSeaport(offer, msg.sender, order, nftContractAddress, fulfillerConduitKey);
    }

    /// @inheritdoc IPurchaseWithFinancing
    function doPurchaseWithFinancingSeaport(
        Offer memory offer,
        address borrower,
        ISeaport.Order calldata order,
        bytes32 fulfillerConduitKey
    ) external payable whenNotPaused nonReentrant {
        _requireSigLendingContract();
        _doPurchaseWithFinancingSeaport(
            offer,
            borrower,
            order,
            order.parameters.offer[0].token,
            fulfillerConduitKey
        );
    }

    function _doPurchaseWithFinancingSeaport(
        Offer memory offer,
        address borrower,
        ISeaport.Order calldata order,
        address nftContractAddress,
        bytes32 fulfillerConduitKey
    ) internal {
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
        
        // fetch purchasing asset address
        address purchasingAsset = order.parameters.consideration[0].token;

        // calculate consideration amount
        uint256 considerationAmount;
        for (uint256 i = 0; i < order.parameters.totalOriginalConsiderationItems; i++) {
            considerationAmount += order.parameters.consideration[i].endAmount;
        }

        // prepare for purchase by increasing allowance to seaport and
        // getting funds from lender and borrower for the considerationAmount
        _prepareForPurchaseWithFinancing(
        offer,
        borrower,
        order.parameters.offer[0].identifierOrCriteria,
        nftContractAddress,
        purchasingAsset,
        considerationAmount,
        seaportContractAddress
        );

        // Purchase NFT
        if (offer.asset == ETH_ADDRESS) {
            require(
                ISeaport(seaportContractAddress).fulfillOrder{ value: considerationAmount }(
                    order,
                    fulfillerConduitKey
                ),
                "00048"
            );
        } else {
            require(
                ISeaport(seaportContractAddress).fulfillOrder(order, fulfillerConduitKey),
                "00048"
            );
        }
        // Transfer purchased NFT to Lending.sol
        _transferNft(
            offer.nftContractAddress,
            order.parameters.offer[0].identifierOrCriteria,
            address(this),
            lendingContractAddress
        );

        emit LoanExecutedSeaport(
            nftContractAddress,
            order.parameters.offer[0].identifierOrCriteria,
            offer
        );
    }

    /// @inheritdoc IPurchaseWithFinancing
    function purchaseWithFinancingSudoswap(
        bytes32 offerHash,
        bool floorTerm,
        ILSSVMPair lssvmPair,
        uint256 nftId
    ) external payable whenNotPaused nonReentrant {
        // fetch nft contract address
        address nftContractAddress = address(lssvmPair.nft());

        // get offer
        Offer memory offer = IOffers(offersContractAddress).getOffer(
            nftContractAddress,
            nftId,
            offerHash,
            floorTerm
        );

        // remove non-floor offer
        if (!offer.floorTerm) {
            _requireMatchingNftId(offer, nftId);
            IOffers(offersContractAddress).removeOffer(
                offer.nftContractAddress,
                nftId,
                offerHash,
                floorTerm
            );
        }
        _doPurchaseWithFinancingSudoswap(offer, msg.sender, lssvmPair, nftId, nftContractAddress);
    }

    /// @inheritdoc IPurchaseWithFinancing
    function doPurchaseWithFinancingSudoswap(
        Offer memory offer,
        address borrower,
        ILSSVMPair lssvmPair,
        uint256 nftId
    ) external payable whenNotPaused nonReentrant {
        _requireSigLendingContract();
        _doPurchaseWithFinancingSudoswap(offer, borrower, lssvmPair, nftId, address(lssvmPair.nft()));
    }

    function _doPurchaseWithFinancingSudoswap(
        Offer memory offer,
        address borrower,
        ILSSVMPair lssvmPair,
        uint256 nftId,
        address nftContractAddress
    ) internal {
        // verify pair provided is a valid clone of sudoswap factory pair template
        ILSSVMPairFactoryLike.PairVariant pairVariant = lssvmPair.pairVariant();
        require(ILSSVMPairFactoryLike(sudoswapFactoryContractAddress).isPair(address(lssvmPair), pairVariant), "00050");

        // fetch purchasing asset address
        address purchasingAsset;
        if (pairVariant == ILSSVMPairFactoryLike.PairVariant.ENUMERABLE_ERC20 || pairVariant == ILSSVMPairFactoryLike.PairVariant.MISSING_ENUMERABLE_ERC20) 
            purchasingAsset = address(lssvmPair.token());

        // calculate consideration amount
        uint256 considerationAmount;
        ( , , , considerationAmount, ) = lssvmPair.getBuyNFTQuote(1);

        // prepare for purchase by increasing allowance to sudoswap router and
        // getting funds from lender and borrower for the considerationAmount
        _prepareForPurchaseWithFinancing(
        offer,
        borrower,
        nftId,
        nftContractAddress,
        purchasingAsset,
        considerationAmount,
        sudoswapRouterContractAddress
        );

        // Purchase the NFT
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = nftId;
        ILSSVMRouter.PairSwapSpecific[] memory pairSwapSpecific = new ILSSVMRouter.PairSwapSpecific[](1);
        pairSwapSpecific[0] = ILSSVMRouter.PairSwapSpecific({pair: lssvmPair, nftIds: nftIds});
        if (offer.asset == ETH_ADDRESS) {
            ILSSVMRouter(sudoswapRouterContractAddress).swapETHForSpecificNFTs{value: considerationAmount}(
                pairSwapSpecific,
                payable(address(this)),
                lendingContractAddress,
                block.timestamp
            );
        } else {
            ILSSVMRouter(sudoswapRouterContractAddress).swapERC20ForSpecificNFTs(
                pairSwapSpecific,
                considerationAmount,
                lendingContractAddress,
                block.timestamp
            );
        }

        emit LoanExecutedSudoswap(
            nftContractAddress,
            nftId,
            offer
        );
    }

    function _prepareForPurchaseWithFinancing(
        Offer memory offer,
        address borrower,
        uint256 nftId,
        address nftContractAddress,
        address purchasingAsset,
        uint256 considerationAmount,
        address routerAddress
        ) internal {
        
        _requireIsNotSanctioned(offer.creator);
        _requireIsNotSanctioned(borrower);
        // requireOfferisValid
        require(offer.asset != address(0), "00004");
        _requireLenderOffer(offer);
        _requireOfferNotExpired(offer);
        _requireMinDurationForOffer(offer);
        // require offer assets matches with requested purchase
        _requireMatchingAsset(offer.asset, purchasingAsset);
        _requireMatchingNFTContract(offer.nftContractAddress, nftContractAddress);

        // require no open loan on requested nft
        LoanAuction memory loanAuction = ILending(lendingContractAddress).getLoanAuction(
            offer.nftContractAddress,
            nftId
        );
        require(loanAuction.lastUpdatedTimestamp == 0, "00006");

        // arrange asset amount from borrower side for the purchase
        uint256 considerationDelta = considerationAmount - offer.amount;
        if (offer.asset == ETH_ADDRESS) {
            require(msg.value >= considerationDelta, "00047");
            if (msg.value > considerationDelta) {
                payable(borrower).sendValue(msg.value - considerationDelta);
            }
        } else {
            IERC20Upgradeable asset = IERC20Upgradeable(offer.asset);
            asset.safeTransferFrom(borrower, address(this), considerationDelta);

            uint256 allowance = asset.allowance(address(this), address(routerAddress));
            if (allowance > 0) {
                asset.safeDecreaseAllowance(routerAddress, allowance);
            }
            asset.safeIncreaseAllowance(routerAddress, considerationAmount);
        }

        // take remaining asset from the lender side
        uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
            offer.asset,
            offer.amount
        );
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);
        ILiquidity(liquidityContractAddress).withdrawCBalance(offer.creator, cAsset, cTokensBurned);
        _ethTransferable = true;
        ILiquidity(liquidityContractAddress).sendValue(offer.asset, offer.amount, address(this));
        _ethTransferable = false;

        // initiate a loan between ledner and borrower
        ILending(lendingContractAddress).createLoan(
            offer,
            nftId,
            offer.creator,
            borrower
        );
    }

    function _transferNft(
        address nftContractAddress,
        uint256 nftId,
        address from,
        address to
    ) internal {
        IERC721Upgradeable(nftContractAddress).safeTransferFrom(from, to, nftId);
    }

    function _requireMatchingNFTContract(address nftAddress1, address nftAddress2) internal pure {
        require(nftAddress1 == nftAddress2, "00102");
    }

    // redundant function to other contracts

    function _requireEthTransferable() internal view {
        require(_ethTransferable, "00043");
    }

    function _requireMatchingNftId(Offer memory offer, uint256 nftId) internal pure {
        require(nftId == offer.nftId, "00022");
    }

    function _requireLenderOffer(Offer memory offer) internal pure {
        require(offer.lenderOffer, "00012");
    }

    function _requireOfferNotExpired(Offer memory offer) internal view {
        require(offer.expiration > SafeCastUpgradeable.toUint32(block.timestamp), "00010");
    }

    function _requireMinDurationForOffer(Offer memory offer) internal pure {
        require(offer.duration >= 1 days, "00011");
    }

    function _requireMatchingAsset(address asset1, address asset2) internal pure {
        if (asset2 == address(0)) {
            require(asset1 == ETH_ADDRESS, "00019");
        } else {
            require(asset1 == asset2, "00019");
        }
    }

    function _requireIsNotSanctioned(address addressToCheck) internal view {
        if (!_sanctionsPause) {
            SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
            bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
            require(!isToSanctioned, "00017");
        }
    }

    function _requireSigLendingContract() internal view {
        require(msg.sender == sigLendingContractAddress, "00031");
    }

    /// @notice This contract needs to accept ETH to acquire enough funds to purchase NFTs
    receive() external payable {
        _requireEthTransferable();
    }
}
