//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "./interfaces/niftyapes/refinance/IRefinance.sol";
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./interfaces/niftyapes/offers/IOffers.sol";
import "./interfaces/sanctions/SanctionsList.sol";

/// @title NiftyApes Refinance
/// @custom:version 1.0
/// @author captnseagraves (captnseagraves.eth)
/// @custom:contributor zishansami102 (zishansami.eth)

contract NiftyApesRefinance is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IRefinance
{
    using AddressUpgradeable for address payable;

    /// @dev Internal address used for for ETH in our mappings
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Internal constant address for the Chainalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    /// @notice The maximum value that any fee on the protocol can be set to.
    ///         Fees on the protocol are denominated in parts of 10_000.
    uint256 private constant MAX_FEE = 1_000;

    /// @notice The base value for fees in the protocol.
    uint256 private constant MAX_BPS = 10_000;

    /// @inheritdoc IRefinance
    address public lendingContractAddress;

    /// @inheritdoc IRefinance
    address public offersContractAddress;

    /// @inheritdoc IRefinance
    address public liquidityContractAddress;

    /// @inheritdoc IRefinance
    address public sigLendingContractAddress;

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
    }

    /// @inheritdoc IRefinanceAdmin
    function updateLiquidityContractAddress(address newLiquidityContractAddress)
        external
        onlyOwner
    {
        require(address(newLiquidityContractAddress) != address(0), "00035");
        emit RefinanceXLiquidityContractAddressUpdated(
            liquidityContractAddress,
            newLiquidityContractAddress
        );
        liquidityContractAddress = newLiquidityContractAddress;
    }

    /// @inheritdoc IRefinanceAdmin
    function updateOffersContractAddress(address newOffersContractAddress) external onlyOwner {
        require(address(newOffersContractAddress) != address(0), "00035");
        emit RefinanceXOffersContractAddressUpdated(
            offersContractAddress,
            newOffersContractAddress
        );
        offersContractAddress = newOffersContractAddress;
    }

    /// @inheritdoc IRefinanceAdmin
    function updateLendingContractAddress(address newLendingContractAddress) external onlyOwner {
        require(address(newLendingContractAddress) != address(0), "00035");
        emit RefinanceXLendingContractAddressUpdated(
            lendingContractAddress,
            newLendingContractAddress
        );
        lendingContractAddress = newLendingContractAddress;
    }

    /// @inheritdoc IRefinanceAdmin
    function updateSigLendingContractAddress(address newSigLendingContractAddress)
        external
        onlyOwner
    {
        require(address(newSigLendingContractAddress) != address(0), "00035");
        emit RefinanceXSigLendingContractAddressUpdated(
            sigLendingContractAddress,
            newSigLendingContractAddress
        );
        sigLendingContractAddress = newSigLendingContractAddress;
    }

    /// @inheritdoc IRefinanceAdmin
    function pauseSanctions() external onlyOwner {
        _sanctionsPause = true;
        emit RefinanceSanctionsPaused();
    }

    /// @inheritdoc IRefinanceAdmin
    function unpauseSanctions() external onlyOwner {
        _sanctionsPause = false;
        emit RefinanceSanctionsUnpaused();
    }

    /// @inheritdoc IRefinanceAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IRefinanceAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IRefinance
    function refinanceByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm,
        bytes32 offerHash,
        uint32 expectedLastUpdatedTimestamp
    ) external whenNotPaused nonReentrant {
        Offer memory offer = _offerNftIdAndCountChecks(
            nftContractAddress,
            nftId,
            floorTerm,
            offerHash
        );

        _doRefinanceByBorrower(offer, nftId, msg.sender, expectedLastUpdatedTimestamp);
    }

    /// @inheritdoc IRefinance
    function doRefinanceByBorrower(
        Offer memory offer,
        uint256 nftId,
        address nftOwner,
        uint32 expectedLastUpdatedTimestamp
    ) external whenNotPaused nonReentrant {
        _requireSigLendingContract();
        _doRefinanceByBorrower(offer, nftId, nftOwner, expectedLastUpdatedTimestamp);
    }

    function _doRefinanceByBorrower(
        Offer memory offer,
        uint256 nftId,
        address nftOwner,
        uint32 expectedLastUpdatedTimestamp
    ) internal {
        ILendingStructs.LoanAuction memory loanAuction = ILending(lendingContractAddress).getLoanAuction(offer.nftContractAddress, nftId);

        _requireIsNotSanctioned(nftOwner);
        _requireIsNotSanctioned(offer.creator);
        _requireMatchingAsset(offer.asset, loanAuction.asset);
        _requireNftOwner(loanAuction, nftOwner);
        _requireNoFixedTerm(loanAuction);
        // requireExpectedTermsAreActive
        if (expectedLastUpdatedTimestamp != 0) {
            require(loanAuction.lastUpdatedTimestamp == expectedLastUpdatedTimestamp, "00026");
        }
        _requireOpenLoan(loanAuction);
        _requireLoanNotExpired(loanAuction);
        _requireOfferNotExpired(offer);
        _requireLenderOffer(offer);
        _requireMinDurationForOffer(offer);

        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);

        uint256 interestThresholdDelta = ILending(lendingContractAddress).checkSufficientInterestAccumulated(offer.nftContractAddress, nftId);

        if (interestThresholdDelta > 0) {
            loanAuction.accumulatedLenderInterest += SafeCastUpgradeable.toUint128(
                interestThresholdDelta
            );
        }

        _updateInterest(loanAuction);

        uint256 toLenderUnderlying = loanAuction.amountDrawn +
            loanAuction.accumulatedLenderInterest +
            loanAuction.slashableLenderInterest +
            ((uint256(loanAuction.amountDrawn) * ILending(lendingContractAddress).originationPremiumBps()) / MAX_BPS);

        uint256 toProtocolUnderlying = loanAuction.unpaidProtocolInterest;

        require(offer.amount >= toLenderUnderlying + toProtocolUnderlying, "00005");

        uint256 toLenderCToken = ILiquidity(liquidityContractAddress).assetAmountToCAssetAmount(
            offer.asset,
            toLenderUnderlying
        );

        uint256 toProtocolCToken = ILiquidity(liquidityContractAddress).assetAmountToCAssetAmount(
            offer.asset,
            toProtocolUnderlying
        );

        ILiquidity(liquidityContractAddress).withdrawCBalance(
            offer.creator,
            cAsset,
            toLenderCToken + toProtocolCToken
        );
        ILiquidity(liquidityContractAddress).addToCAssetBalance(
            loanAuction.lender,
            cAsset,
            toLenderCToken
        );
        ILiquidity(liquidityContractAddress).addToCAssetBalance(owner(), cAsset, toProtocolCToken);

        uint128 currentAmountDrawn = loanAuction.amountDrawn;

        // update Loan struct
        if (loanAuction.lenderRefi) {
            loanAuction.lenderRefi = false;
        }
        loanAuction.lender = offer.creator;
        loanAuction.amount = offer.amount;
        loanAuction.interestRatePerSecond = offer.interestRatePerSecond;
        loanAuction.loanEndTimestamp = _currentTimestamp32() + offer.duration;
        loanAuction.loanBeginTimestamp = _currentTimestamp32();
        loanAuction.amountDrawn = SafeCastUpgradeable.toUint128(
            toLenderUnderlying + toProtocolUnderlying
        );
        loanAuction.accumulatedLenderInterest = 0;
        loanAuction.accumulatedPaidProtocolInterest = 0;
        loanAuction.unpaidProtocolInterest = 0;
        if (offer.fixedTerms) {
            loanAuction.fixedTerms = offer.fixedTerms;
        }
        if (loanAuction.slashableLenderInterest > 0) {
            loanAuction.slashableLenderInterest = 0;
        }

        ILending(lendingContractAddress).updateLoanAuctionInternal(offer.nftContractAddress, nftId, loanAuction);

        emit Refinance(offer.nftContractAddress, nftId, loanAuction);

        ILending(lendingContractAddress).emitAmountDrawnInternal(
            offer.nftContractAddress,
            nftId,
            loanAuction.amountDrawn - currentAmountDrawn,
            loanAuction
        );
    }

    /// @inheritdoc IRefinance
    function refinanceByLender(Offer memory offer, uint32 expectedLastUpdatedTimestamp)
        external
        whenNotPaused
        nonReentrant
    {
        ILendingStructs.LoanAuction memory loanAuction = ILending(lendingContractAddress).getLoanAuction(offer.nftContractAddress, offer.nftId);

        _requireIsNotSanctioned(msg.sender);
        _requireOpenLoan(loanAuction);
        // requireExpectedTermsAreActive
        if (expectedLastUpdatedTimestamp != 0) {
            require(loanAuction.lastUpdatedTimestamp == expectedLastUpdatedTimestamp, "00026");
        }
        _requireOfferCreator(offer, msg.sender);
        _requireLenderOffer(offer);
        _requireLoanNotExpired(loanAuction);
        _requireOfferNotExpired(offer);
        _requireOfferParity(loanAuction, offer);
        _requireNoFixedTerm(loanAuction);
        _requireNoFloorTerms(offer);
        _requireMatchingAsset(offer.asset, loanAuction.asset);
        // requireNoFixTermOffer
        require(!offer.fixedTerms, "00016");

        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);

        // check how much, if any, gasGriefing premium should be applied
        uint256 interestThresholdDelta = ILending(lendingContractAddress).checkSufficientInterestAccumulated(offer.nftContractAddress, offer.nftId);

        // check whether a termGriefing premium should apply
        bool sufficientTerms = ILending(lendingContractAddress).checkSufficientTerms(
            offer.nftContractAddress,
            offer.nftId,
            offer.amount,
            offer.interestRatePerSecond,
            offer.duration
        );

        _updateInterest(loanAuction);

        // set lenderRefi to true to signify the last action to occur in the loan was a lenderRefinance
        loanAuction.lenderRefi = true;

        uint256 protocolInterestAndPremium;
        uint256 protocolPremiumInCtokens;

        if (!sufficientTerms) {
            protocolInterestAndPremium +=
                (uint256(loanAuction.amountDrawn) * ILending(lendingContractAddress).termGriefingPremiumBps()) /
                MAX_BPS;
        }

        // update LoanAuction struct
        loanAuction.amount = offer.amount;
        loanAuction.interestRatePerSecond = offer.interestRatePerSecond;
        loanAuction.loanEndTimestamp = loanAuction.loanBeginTimestamp + offer.duration;

        if (loanAuction.lender == offer.creator) {
            uint256 additionalTokens = ILiquidity(liquidityContractAddress)
                .assetAmountToCAssetAmount(offer.asset, offer.amount - loanAuction.amountDrawn);

            // This value is only a termGriefing if applicable
            protocolPremiumInCtokens = ILiquidity(liquidityContractAddress)
                .assetAmountToCAssetAmount(offer.asset, protocolInterestAndPremium);

            _requireSufficientBalance(
                offer.creator,
                cAsset,
                additionalTokens + protocolPremiumInCtokens
            );

            ILiquidity(liquidityContractAddress).withdrawCBalance(
                offer.creator,
                cAsset,
                protocolPremiumInCtokens
            );
            ILiquidity(liquidityContractAddress).addToCAssetBalance(
                owner(),
                cAsset,
                protocolPremiumInCtokens
            );
        } else {
            // If refinance is done by a new lender and refinacneByLender was the last action to occur, add slashableInterest to accumulated interest
            if (loanAuction.slashableLenderInterest > 0) {
                loanAuction.accumulatedLenderInterest += loanAuction.slashableLenderInterest;
                loanAuction.slashableLenderInterest = 0;
            }
            // calculate the value to pay out to the current lender, this includes the protocolInterest, which is paid out each refinance,
            // and reimbursed by the borrower at the end of the loan.
            uint256 interestAndPremiumOwedToCurrentLender = uint256(
                loanAuction.accumulatedLenderInterest
            ) +
                loanAuction.accumulatedPaidProtocolInterest +
                ((uint256(loanAuction.amountDrawn) * ILending(lendingContractAddress).originationPremiumBps()) / MAX_BPS);

            // add protocolInterest
            protocolInterestAndPremium += loanAuction.unpaidProtocolInterest;

            // add gasGriefing premium
            if (interestThresholdDelta > 0) {
                interestAndPremiumOwedToCurrentLender += interestThresholdDelta;
            }

            // add default premium
            if (_currentTimestamp32() > loanAuction.loanEndTimestamp - 1 hours) {
                protocolInterestAndPremium +=
                    (uint256(loanAuction.amountDrawn) * ILending(lendingContractAddress).defaultRefinancePremiumBps()) /
                    MAX_BPS;
            }

            uint256 fullCTokenAmountRequired = ILiquidity(liquidityContractAddress)
                .assetAmountToCAssetAmount(
                    offer.asset,
                    interestAndPremiumOwedToCurrentLender +
                        protocolInterestAndPremium +
                        loanAuction.amount
                );

            uint256 fullCTokenAmountToWithdraw = ILiquidity(liquidityContractAddress)
                .assetAmountToCAssetAmount(
                    offer.asset,
                    interestAndPremiumOwedToCurrentLender +
                        protocolInterestAndPremium +
                        loanAuction.amountDrawn
                );

            // require prospective lender has sufficient available balance to refinance loan
            _requireSufficientBalance(offer.creator, cAsset, fullCTokenAmountRequired);

            protocolPremiumInCtokens = ILiquidity(liquidityContractAddress)
                .assetAmountToCAssetAmount(offer.asset, protocolInterestAndPremium);

            address currentlender = loanAuction.lender;

            // update LoanAuction lender
            loanAuction.lender = offer.creator;

            ILiquidity(liquidityContractAddress).withdrawCBalance(
                offer.creator,
                cAsset,
                fullCTokenAmountToWithdraw
            );

            ILiquidity(liquidityContractAddress).addToCAssetBalance(
                currentlender,
                cAsset,
                (fullCTokenAmountToWithdraw - protocolPremiumInCtokens)
            );

            ILiquidity(liquidityContractAddress).addToCAssetBalance(
                owner(),
                cAsset,
                protocolPremiumInCtokens
            );

            loanAuction.accumulatedPaidProtocolInterest += loanAuction.unpaidProtocolInterest;
            loanAuction.unpaidProtocolInterest = 0;
        }
        
        ILending(lendingContractAddress).updateLoanAuctionInternal(offer.nftContractAddress, offer.nftId, loanAuction);

        emit Refinance(offer.nftContractAddress, offer.nftId, loanAuction);
    }

    function _offerNftIdAndCountChecks(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm,
        bytes32 offerHash
    ) internal returns (Offer memory) {
        Offer memory offer = IOffers(offersContractAddress).getOffer(
            nftContractAddress,
            nftId,
            offerHash,
            floorTerm
        );

        if (!offer.floorTerm) {
            _requireMatchingNftId(offer, nftId);
            IOffers(offersContractAddress).removeOffer(
                nftContractAddress,
                nftId,
                offerHash,
                floorTerm
            );
        } else {
            require(
                IOffers(offersContractAddress).getFloorOfferCount(offerHash) < offer.floorTermLimit,
                "00051"
            );

            IOffers(offersContractAddress).incrementFloorOfferCount(offerHash);
        }

        return offer;
    }

    
    function _updateInterest(ILendingStructs.LoanAuction memory loanAuction)
        internal view
        returns (uint256 lenderInterest, uint256 protocolInterest)
    {
        (lenderInterest, protocolInterest) = _calculateInterestAccrued(loanAuction);

        if (loanAuction.lenderRefi == true) {
            loanAuction.slashableLenderInterest += SafeCastUpgradeable.toUint128(lenderInterest);
        } else {
            loanAuction.accumulatedLenderInterest += SafeCastUpgradeable.toUint128(lenderInterest);
        }

        loanAuction.unpaidProtocolInterest += SafeCastUpgradeable.toUint128(protocolInterest);
        loanAuction.lastUpdatedTimestamp = _currentTimestamp32();
    }

    function _requireSufficientBalance(
        address creator,
        address cAsset,
        uint256 amount
    ) internal view {
        require(
            ILiquidity(liquidityContractAddress).getCAssetBalance(creator, cAsset) >= amount,
            "00001"
        );
    }

    function _calculateInterestAccrued(ILendingStructs.LoanAuction memory loanAuction)
        internal
        view
        returns (uint256 lenderInterest, uint256 protocolInterest)
    {
        uint256 timePassed = _currentTimestamp32() - loanAuction.lastUpdatedTimestamp;

        lenderInterest = (timePassed * loanAuction.interestRatePerSecond);
        protocolInterest = (timePassed * loanAuction.protocolInterestRatePerSecond);
    }

    function _requireOpenLoan(ILendingStructs.LoanAuction memory loanAuction) internal pure {
        require(loanAuction.lastUpdatedTimestamp != 0, "00007");
    }

    function _requireLoanNotExpired(ILendingStructs.LoanAuction memory loanAuction) internal view {
        require(_currentTimestamp32() < loanAuction.loanEndTimestamp, "00009");
    }

    function _requireOfferNotExpired(Offer memory offer) internal view {
        require(offer.expiration > SafeCastUpgradeable.toUint32(block.timestamp), "00010");
    }

    function _requireMinDurationForOffer(Offer memory offer) internal pure {
        require(offer.duration >= 1 days, "00011");
    }

    function _requireLenderOffer(Offer memory offer) internal pure {
        require(offer.lenderOffer, "00012");
    }

    function _requireNoFloorTerms(Offer memory offer) internal pure {
        require(!offer.floorTerm, "00014");
    }

    function _requireNoFixedTerm(ILendingStructs.LoanAuction memory loanAuction) internal pure {
        require(!loanAuction.fixedTerms, "00015");
    }

    function _requireMatchingAsset(address asset1, address asset2) internal pure {
        require(asset1 == asset2, "00019");
    }

    function _requireNftOwner(ILendingStructs.LoanAuction memory loanAuction, address nftOwner) internal pure {
        require(nftOwner == loanAuction.nftOwner, "00021");
    }

    function _requireMatchingNftId(Offer memory offer, uint256 nftId) internal pure {
        require(nftId == offer.nftId, "00022");
    }

    function _requireOfferCreator(Offer memory offer, address creator) internal pure {
        require(creator == offer.creator, "00024");
    }

    function _requireSigLendingContract() internal view {
        require(msg.sender == sigLendingContractAddress, "00031");
    }

    function _requireOfferParity(ILendingStructs.LoanAuction memory loanAuction, Offer memory offer)
        internal
        pure
    {
        // Caching fields here for gas usage
        uint128 amount = loanAuction.amount;
        uint96 interestRatePerSecond = loanAuction.interestRatePerSecond;
        uint32 loanEndTime = loanAuction.loanEndTimestamp;
        uint32 offerEndTime = loanAuction.loanBeginTimestamp + offer.duration;

        // Better amount
        if (
            offer.amount > amount &&
            offer.interestRatePerSecond <= interestRatePerSecond &&
            offerEndTime >= loanEndTime
        ) {
            return;
        }

        // Lower interest rate
        if (
            offer.amount >= amount &&
            offer.interestRatePerSecond < interestRatePerSecond &&
            offerEndTime >= loanEndTime
        ) {
            return;
        }

        // Longer duration
        if (
            offer.amount >= amount &&
            offer.interestRatePerSecond <= interestRatePerSecond &&
            offerEndTime > loanEndTime
        ) {
            return;
        }

        revert("00025");
    }

    function _requireIsNotSanctioned(address addressToCheck) internal view {
        if (!_sanctionsPause) {
            SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
            bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
            require(!isToSanctioned, "00017");
        }
    }

    function _currentTimestamp32() internal view returns (uint32) {
        return SafeCastUpgradeable.toUint32(block.timestamp);
    }
}
