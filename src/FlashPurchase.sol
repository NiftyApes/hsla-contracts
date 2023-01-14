//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "./interfaces/niftyapes/flashPurchase/IFlashPurchase.sol";
import "./interfaces/niftyapes/lending/ILending.sol";
import "./interfaces/niftyapes/sigLending/ISigLending.sol";
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./interfaces/niftyapes/offers/IOffers.sol";
import "./interfaces/sanctions/SanctionsList.sol";
import "./flashPurchase/interfaces/IFlashPurchaseReceiver.sol";

/// @notice Extension of NiftApes lending contract to allow purchase of NFTs with lending offer funds
/// @title NiftyApes FlashPurchase
/// @custom:version 1.0
/// @author captnseagraves (captnseagraves.eth)
/// @custom:contributor zishansami102 (zishansami.eth)
/// @custom:contributor jyturley
contract NiftyApesFlashPurchase is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    IFlashPurchase
{
    /// @dev Internal address used for for ETH
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Internal constant address for the Chainalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    /// @inheritdoc IFlashPurchase
    address public offersContractAddress;

    /// @inheritdoc IFlashPurchase
    address public liquidityContractAddress;

    /// @inheritdoc IFlashPurchase
    address public lendingContractAddress;

    /// @inheritdoc IFlashPurchase
    address public sigLendingContractAddress;

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
    function initialize() public initializer {
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }

    /// @inheritdoc IFlashPurchaseAdmin
    function updateLiquidityContractAddress(address newLiquidityContractAddress)
        external
        onlyOwner
    {
        require(address(newLiquidityContractAddress) != address(0), "00035");
        emit FlashPurchaseXLiquidityContractAddressUpdated(
            liquidityContractAddress,
            newLiquidityContractAddress
        );
        liquidityContractAddress = newLiquidityContractAddress;
    }

    /// @inheritdoc IFlashPurchaseAdmin
    function updateOffersContractAddress(address newOffersContractAddress) external onlyOwner {
        require(address(newOffersContractAddress) != address(0), "00035");
        emit FlashPurchaseXOffersContractAddressUpdated(
            offersContractAddress,
            newOffersContractAddress
        );
        offersContractAddress = newOffersContractAddress;
    }

    /// @inheritdoc IFlashPurchaseAdmin
    function updateLendingContractAddress(address newLendingContractAddress) external onlyOwner {
        require(address(newLendingContractAddress) != address(0), "00035");
        emit FlashPurchaseXLendingContractAddressUpdated(
            lendingContractAddress,
            newLendingContractAddress
        );
        lendingContractAddress = newLendingContractAddress;
    }

    /// @inheritdoc IFlashPurchaseAdmin
    function updateSigLendingContractAddress(address newSigLendingContractAddress)
        external
        onlyOwner
    {
        require(address(newSigLendingContractAddress) != address(0), "00035");
        emit FlashPurchaseXSigLendingContractAddressUpdated(
            sigLendingContractAddress,
            newSigLendingContractAddress
        );
        sigLendingContractAddress = newSigLendingContractAddress;
    }

    /// @inheritdoc IFlashPurchaseAdmin
    function pauseSanctions() external onlyOwner {
        _sanctionsPause = true;
        emit FlashPurchaseSanctionsPaused();
    }

    /// @inheritdoc IFlashPurchaseAdmin
    function unpauseSanctions() external onlyOwner {
        _sanctionsPause = false;
        emit FlashPurchaseSanctionsUnpaused();
    }

    /// @inheritdoc IFlashPurchaseAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IFlashPurchaseAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IFlashPurchase
    function borrowFundsForPurchase(
        bytes32 offerHash,
        uint256 nftId,
        address receiver,
        address borrower,
        bytes calldata data
    ) external whenNotPaused nonReentrant {
        Offer memory offer = _fetchAndRemoveNonFloorOffer(
            offerHash,
            nftId
        );
        _doBorrow(offer, nftId, receiver, borrower, data);
    }

    /// @inheritdoc IFlashPurchase
    function borrowSignature(
        Offer memory offer,
        bytes memory signature,
        uint256 nftId,
        address receiver,
        address borrower,
        bytes calldata data
    ) external whenNotPaused nonReentrant {
        ISigLending(sigLendingContractAddress).validateAndUseOfferSignatureFlashPurchase(offer, signature);
        _doBorrow(offer, nftId, receiver, borrower, data);
    }

    function _doBorrow(
        Offer memory offer,
        uint256 nftId,
        address receiver,
        address borrower,
        bytes calldata data
    ) internal {
        _requireIsNotSanctioned(offer.creator);
        _requireIsNotSanctioned(borrower);
        _requireIsNotSanctioned(receiver);
        // requireOfferisValid
        require(offer.asset != address(0), "00004");
        _requireLenderOffer(offer);
        _requireOfferNotExpired(offer);
        _requireMinDurationForOffer(offer);
        if (!offer.floorTerm) {
            _requireMatchingNftId(offer, nftId);
        }
        
        LoanAuction memory loanAuction = ILending(lendingContractAddress).getLoanAuction(
            offer.nftContractAddress,
            nftId
        );
        // requireNoOpenLoan
        require(loanAuction.lastUpdatedTimestamp == 0, "00006");

        // redeem required underlying asset from Compound
        uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
            offer.asset,
            offer.amount
        );
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);
        // subtract loaned amount from lender's balance
        ILiquidity(liquidityContractAddress).withdrawCBalance(offer.creator, cAsset, cTokensBurned);

        // initiate a loan between lender and borrower
        ILending(lendingContractAddress).createLoanFlashPurchase(
            offer,
            nftId,
            offer.creator,
            borrower
        );

        // send funds to reciever
        ILiquidity(liquidityContractAddress).sendValue(offer.asset, offer.amount, receiver);

        // execute opreation on receiver contract
        require(IFlashPurchaseReceiver(receiver).executeOperation(
            offer.nftContractAddress,
            nftId,
            msg.sender,
            data
        ), "00052");
        
        // Transfer nft from receiver contract to lending contract as collateral, revert on failure
        _transferNft(
            offer.nftContractAddress,
            nftId,
            receiver,
            lendingContractAddress
        );

        loanAuction = ILending(lendingContractAddress).getLoanAuction(
            offer.nftContractAddress,
            nftId
        );

        emit LoanExecutedForPurchase(
            offer.nftContractAddress,
            nftId,
            receiver,
            loanAuction
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

    function _fetchAndRemoveNonFloorOffer(
        bytes32 offerHash,
        uint256 nftId
    ) internal returns(Offer memory offer) {
        // fetch offer
        offer = IOffers(offersContractAddress).getOffer(offerHash);

        // remove non-floor offer
        if (!offer.floorTerm) {
            _requireMatchingNftId(offer, nftId);
            IOffers(offersContractAddress).removeOffer(offerHash);
        } else {
            require(
                IOffers(offersContractAddress).getFloorOfferCount(offerHash) < offer.floorTermLimit,
                "00051"
            );

            IOffers(offersContractAddress).incrementFloorOfferCount(offerHash);
        }
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

    function _requireIsNotSanctioned(address addressToCheck) internal view {
        if (!_sanctionsPause) {
            SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
            bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
            require(!isToSanctioned, "00017");
        }
    }

    /// @notice This contract needs to accept ETH to acquire enough funds to purchase NFTs
    receive() external payable {
        _requireEthTransferable();
    }
}
