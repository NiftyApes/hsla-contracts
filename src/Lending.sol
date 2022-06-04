//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "./interfaces/niftyapes/lending/ILending.sol";
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./interfaces/niftyapes/offers/IOffers.sol";
import "./interfaces/sanctions/SanctionsList.sol";

import "./test/Console.sol";

/// @title Implemention of the ILending interface
contract NiftyApesLending is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    ILending
{
    using AddressUpgradeable for address payable;

    /// @dev Internal address used for for ETH in our mappings
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Internal constant address for the Chinalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    /// @notice The maximum value that any fee on the protocol can be set to.
    ///         Fees on the protocol are denomimated in parts of 10_000.
    uint256 private constant MAX_FEE = 1_000;

    /// @notice The base value for fees in the protocol.
    uint256 private constant MAX_BPS = 10_000;

    /// @dev A mapping for a NFT to a loan auction.
    ///      The mapping has to be broken into two parts since an NFT is denomiated by its address (first part)
    ///      and its nftId (second part) in our code base.
    mapping(address => mapping(uint256 => LoanAuction)) private _loanAuctions;

    /// @inheritdoc ILending
    address public offersContractAddress;

    /// @inheritdoc ILending
    address public liquidityContractAddress;

    /// @inheritdoc ILending
    uint96 public protocolInterestBps;

    /// @inheritdoc ILending
    uint16 public originationPremiumBps;

    /// @inheritdoc ILending
    uint16 public gasGriefingPremiumBps;

    /// @inheritdoc ILending
    uint16 public gasGriefingProtocolPremiumBps;

    /// @inheritdoc ILending
    uint16 public termGriefingPremiumBps;

    /// @inheritdoc ILending
    uint16 public defaultRefinancePremiumBps;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the NiftyApes protocol.
    ///         Nifty Apes is intended to be deployed behind a proxy amd thus needs to initialize
    ///         its state outsize of a constructor.
    function initialize() public initializer {
        protocolInterestBps = 0;
        originationPremiumBps = 50;
        gasGriefingPremiumBps = 25;
        gasGriefingProtocolPremiumBps = 0;
        termGriefingPremiumBps = 25;
        defaultRefinancePremiumBps = 25;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    }

    /// @inheritdoc ILendingAdmin
    function updateProtocolInterestBps(uint96 newProtocolInterestBps) external onlyOwner {
        emit ProtocolInterestBpsUpdated(protocolInterestBps, newProtocolInterestBps);
        protocolInterestBps = newProtocolInterestBps;
    }

    /// @inheritdoc ILendingAdmin
    function updateOriginationPremiumLenderBps(uint16 newOriginationPremiumBps) external onlyOwner {
        require(newOriginationPremiumBps <= MAX_FEE, "max fee");
        emit OriginationPremiumBpsUpdated(originationPremiumBps, newOriginationPremiumBps);
        originationPremiumBps = newOriginationPremiumBps;
    }

    /// @inheritdoc ILendingAdmin
    function updateGasGriefingPremiumBps(uint16 newGasGriefingPremiumBps) external onlyOwner {
        require(newGasGriefingPremiumBps <= MAX_FEE, "max fee");
        emit GasGriefingPremiumBpsUpdated(gasGriefingPremiumBps, newGasGriefingPremiumBps);
        gasGriefingPremiumBps = newGasGriefingPremiumBps;
    }

    /// @inheritdoc ILendingAdmin
    function updateGasGriefingProtocolPremiumBps(uint16 newGasGriefingProtocolPremiumBps)
        external
        onlyOwner
    {
        require(newGasGriefingProtocolPremiumBps <= MAX_FEE, "max fee");
        emit GasGriefingProtocolPremiumBpsUpdated(
            gasGriefingProtocolPremiumBps,
            newGasGriefingProtocolPremiumBps
        );
        gasGriefingProtocolPremiumBps = newGasGriefingProtocolPremiumBps;
    }

    /// @inheritdoc ILendingAdmin
    function updateDefaultRefinancePremiumBps(uint16 newDefaultRefinancePremiumBps)
        external
        onlyOwner
    {
        require(newDefaultRefinancePremiumBps <= MAX_FEE, "max fee");
        emit DefaultRefinancePremiumBpsUpdated(
            defaultRefinancePremiumBps,
            newDefaultRefinancePremiumBps
        );
        defaultRefinancePremiumBps = newDefaultRefinancePremiumBps;
    }

    /// @inheritdoc ILendingAdmin
    function updateTermGriefingPremiumBps(uint16 newTermGriefingPremiumBps) external onlyOwner {
        require(newTermGriefingPremiumBps <= MAX_FEE, "max fee");
        emit TermGriefingPremiumBpsUpdated(termGriefingPremiumBps, newTermGriefingPremiumBps);
        termGriefingPremiumBps = newTermGriefingPremiumBps;
    }

    /// @inheritdoc ILendingAdmin
    function updateOffersContractAddress(address newOffersContractAddress) external onlyOwner {
        emit LendingXOffersContractAddressUpdated(offersContractAddress, newOffersContractAddress);
        offersContractAddress = newOffersContractAddress;
    }

    /// @inheritdoc ILendingAdmin
    function updateLiquidityContractAddress(address newLiquidityContractAddress)
        external
        onlyOwner
    {
        emit LendingXLiquidityContractAddressUpdated(
            liquidityContractAddress,
            newLiquidityContractAddress
        );
        liquidityContractAddress = newLiquidityContractAddress;
    }

    /// @inheritdoc ILendingAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc ILendingAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc ILending
    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory)
    {
        return getLoanAuctionInternal(nftContractAddress, nftId);
    }

    function getLoanAuctionInternal(address nftContractAddress, uint256 nftId)
        internal
        view
        returns (LoanAuction storage)
    {
        return _loanAuctions[nftContractAddress][nftId];
    }

    /// @inheritdoc ILending
    function executeLoanByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external payable whenNotPaused nonReentrant {
        Offer memory offer = IOffers(offersContractAddress).getOffer(
            nftContractAddress,
            nftId,
            offerHash,
            floorTerm
        );

        requireLenderOffer(offer);

        // Remove the offer from storage, saving gas
        // We can only do this for non floor offers since
        // a floor offer can be used for multiple nfts
        if (!offer.floorTerm) {
            requireMatchingNftId(offer, nftId);
            IOffers(offersContractAddress).removeOffer(
                nftContractAddress,
                nftId,
                offerHash,
                floorTerm
            );
        }
        _executeLoanInternal(offer, offer.creator, msg.sender, nftId);
    }

    /// @inheritdoc ILending
    function executeLoanByBorrowerSignature(
        Offer memory offer,
        bytes memory signature,
        uint256 nftId
    ) external payable whenNotPaused nonReentrant {
        address lender = IOffers(offersContractAddress).getOfferSigner(offer, signature);

        requireOfferCreator(offer, lender);
        IOffers(offersContractAddress).requireAvailableSignature(signature);
        IOffers(offersContractAddress).requireSignature65(signature);
        requireLenderOffer(offer);

        if (!offer.floorTerm) {
            requireMatchingNftId(offer, nftId);
            IOffers(offersContractAddress).markSignatureUsed(offer, signature);
        }

        // execute state changes for executeLoanByBid
        _executeLoanInternal(offer, lender, msg.sender, nftId);
    }

    /// @inheritdoc ILending
    function executeLoanByLender(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) public payable whenNotPaused nonReentrant {
        Offer memory offer = IOffers(offersContractAddress).getOffer(
            nftContractAddress,
            nftId,
            offerHash,
            floorTerm
        );

        requireBorrowerOffer(offer);
        requireNoFloorTerms(offer);

        IOffers(offersContractAddress).removeOffer(nftContractAddress, nftId, offerHash, floorTerm);

        _executeLoanInternal(offer, msg.sender, offer.creator, nftId);
    }

    /// @inheritdoc ILending
    function executeLoanByLenderSignature(Offer memory offer, bytes memory signature)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        address borrower = IOffers(offersContractAddress).getOfferSigner(offer, signature);

        requireOfferCreator(offer, borrower);
        IOffers(offersContractAddress).requireAvailableSignature(signature);
        requireSignature65(signature);
        requireBorrowerOffer(offer);
        requireNoFloorTerms(offer);

        IOffers(offersContractAddress).markSignatureUsed(offer, signature);

        _executeLoanInternal(offer, msg.sender, borrower, offer.nftId);
    }

    function _executeLoanInternal(
        Offer memory offer,
        address lender,
        address borrower,
        uint256 nftId
    ) internal {
        requireIsNotSanctioned(lender);
        requireIsNotSanctioned(borrower);
        requireOfferPresent(offer);

        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);

        LoanAuction storage loanAuction = getLoanAuctionInternal(offer.nftContractAddress, nftId);

        requireNoOpenLoan(loanAuction);
        requireOfferNotExpired(offer);
        requireMinDurationForOffer(offer);
        require721Owner(offer.nftContractAddress, nftId, borrower);

        createLoan(loanAuction, offer, lender, borrower);

        transferNft(offer.nftContractAddress, nftId, borrower, address(this));

        uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
            offer.asset,
            offer.amount
        );
        ILiquidity(liquidityContractAddress).withdrawCBalance(lender, cAsset, cTokensBurned);

        ILiquidity(liquidityContractAddress).sendValue(offer.asset, offer.amount, borrower);

        emit LoanExecuted(lender, offer.asset, borrower, offer.nftContractAddress, nftId, offer);

        emit AmountDrawn(borrower, offer.nftContractAddress, nftId, offer.amount, offer.amount);
    }

    /// @inheritdoc ILending
    function refinanceByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm,
        bytes32 offerHash
    ) external whenNotPaused nonReentrant {
        Offer memory offer = IOffers(offersContractAddress).getOffer(
            nftContractAddress,
            nftId,
            offerHash,
            floorTerm
        );

        requireLenderOffer(offer);

        if (!offer.floorTerm) {
            requireMatchingNftId(offer, nftId);
            // Only removing the offer if its not a floor term offer
            // Floor term offers can be used for multiple nfts
            IOffers(offersContractAddress).removeOffer(
                nftContractAddress,
                nftId,
                offerHash,
                floorTerm
            );
        }

        _refinanceByBorrower(offer, offer.creator, nftId);
    }

    /// @inheritdoc ILending
    function refinanceByBorrowerSignature(
        Offer memory offer,
        bytes memory signature,
        uint256 nftId
    ) external whenNotPaused nonReentrant {
        address signer = IOffers(offersContractAddress).getOfferSigner(offer, signature);

        requireOfferCreator(offer, signer);
        IOffers(offersContractAddress).requireAvailableSignature(signature);
        requireSignature65(signature);
        requireLenderOffer(offer);

        if (!offer.floorTerm) {
            requireMatchingNftId(offer, nftId);
            IOffers(offersContractAddress).markSignatureUsed(offer, signature);
        }

        _refinanceByBorrower(offer, offer.creator, nftId);
    }

    function _refinanceByBorrower(
        Offer memory offer,
        address newLender,
        uint256 nftId
    ) internal {
        LoanAuction storage loanAuction = getLoanAuctionInternal(offer.nftContractAddress, nftId);
        requireIsNotSanctioned(msg.sender);
        requireMatchingAsset(offer.asset, loanAuction.asset);
        requireNftOwner(loanAuction, msg.sender);
        requireNoFixedTerm(loanAuction);
        requireOpenLoan(loanAuction);
        requireOfferNotExpired(offer);
        requireLenderOffer(offer);
        requireMinDurationForOffer(offer);

        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);

        updateInterest(loanAuction);

        uint256 fullAmount = loanAuction.amountDrawn +
            loanAuction.accumulatedLenderInterest +
            loanAuction.accumulatedProtocolInterest;

        requireOfferAmount(offer, fullAmount);

        uint256 fullCTokenAmount = ILiquidity(liquidityContractAddress).assetAmountToCAssetAmount(
            offer.asset,
            fullAmount
        );

        ILiquidity(liquidityContractAddress).withdrawCBalance(newLender, cAsset, fullCTokenAmount);
        ILiquidity(liquidityContractAddress).addToCAssetBalance(
            loanAuction.lender,
            cAsset,
            fullCTokenAmount
        );

        // update Loan state
        if (loanAuction.lenderRefi) {
            loanAuction.lenderRefi = false;
        }
        loanAuction.lender = newLender;
        loanAuction.amount = offer.amount;
        loanAuction.interestRatePerSecond = offer.interestRatePerSecond;
        loanAuction.loanEndTimestamp = loanAuction.loanBeginTimestamp + offer.duration;
        loanAuction.amountDrawn = SafeCastUpgradeable.toUint128(fullAmount);
        loanAuction.accumulatedLenderInterest = 0;
        if (offer.fixedTerms) {
            loanAuction.fixedTerms = offer.fixedTerms;
        }

        emit Refinance(
            newLender,
            offer.asset,
            loanAuction.nftOwner,
            offer.nftContractAddress,
            nftId,
            offer
        );

        emit AmountDrawn(
            loanAuction.nftOwner,
            offer.nftContractAddress,
            nftId,
            loanAuction.accumulatedLenderInterest + loanAuction.accumulatedProtocolInterest,
            loanAuction.amountDrawn
        );
    }

    /// @inheritdoc ILending
    function refinanceByLender(Offer memory offer) external whenNotPaused nonReentrant {
        LoanAuction storage loanAuction = getLoanAuctionInternal(
            offer.nftContractAddress,
            offer.nftId
        );

        requireIsNotSanctioned(msg.sender);
        requireOpenLoan(loanAuction);
        requireOfferCreator(offer, msg.sender);
        requireLenderOffer(offer);
        requireLoanNotExpired(loanAuction);
        requireOfferNotExpired(offer);
        requireOfferParity(loanAuction, offer);
        requireNoFixedTerm(loanAuction);
        requireNoFloorTerms(offer);
        requireMatchingAsset(offer.asset, loanAuction.asset);
        requireNoFixTermOffer(offer);

        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);

        (
            bool sufficientInterest,
            uint256 lenderInterest,
            uint96 interestThreshold
        ) = checkSufficientInterestAccumulated(loanAuction);
        bool sufficientTerms = checkSufficientTerms(
            loanAuction,
            offer.amount,
            offer.interestRatePerSecond,
            offer.duration
        );

        (, uint256 protocolInterest) = updateInterest(loanAuction);

        // update LoanAuction struct
        loanAuction.amount = offer.amount;
        loanAuction.interestRatePerSecond = offer.interestRatePerSecond;
        loanAuction.loanEndTimestamp = loanAuction.loanBeginTimestamp + offer.duration;
        loanAuction.lenderRefi = true;

        if (loanAuction.lender == offer.creator) {
            // If current lender is refinancing the loan they do not need to pay any fees or buy themselves out.
            // require prospective lender has sufficient available balance to refinance loan
            uint256 additionalTokens = ILiquidity(liquidityContractAddress)
                .assetAmountToCAssetAmount(offer.asset, offer.amount - loanAuction.amountDrawn);

            require(
                ILiquidity(liquidityContractAddress).getCAssetBalance(offer.creator, cAsset) >=
                    additionalTokens,
                "lender balance"
            );
        } else {
            // TODO: (captnseagraves) re-examine the lenderPremium here, can a lender lose money here?
            //        if a borrower pays back some and then the lender gets refinanced, do they lose money?
            // calculate interest earned
            uint256 interestAndPremiumOwedToCurrentLender = loanAuction.accumulatedLenderInterest +
                loanAuction.accumulatedProtocolInterest +
                ((loanAuction.amountDrawn * originationPremiumBps) / MAX_BPS);
            uint256 protocolInterestAndPremium = protocolInterest;

            if (!sufficientInterest) {
                interestAndPremiumOwedToCurrentLender += interestThreshold - lenderInterest;
                protocolInterestAndPremium +=
                    (lenderInterest * gasGriefingProtocolPremiumBps) /
                    MAX_BPS;
            }
            if (!sufficientTerms) {
                protocolInterestAndPremium +=
                    (loanAuction.amountDrawn * termGriefingPremiumBps) /
                    MAX_BPS;
            }

            if (block.timestamp > loanAuction.loanEndTimestamp - 1 hours) {
                protocolInterestAndPremium +=
                    (loanAuction.amountDrawn * defaultRefinancePremiumBps) /
                    MAX_BPS;
            }

            // calculate fullRefinanceAmount
            uint256 fullAmount = interestAndPremiumOwedToCurrentLender +
                protocolInterestAndPremium +
                loanAuction.amountDrawn;

            // If refinancing is done by another lender they must buy out the loan and pay fees
            uint256 fullCTokenAmount = ILiquidity(liquidityContractAddress)
                .assetAmountToCAssetAmount(offer.asset, fullAmount);

            // require prospective lender has sufficient available balance to refinance loan
            require(
                ILiquidity(liquidityContractAddress).getCAssetBalance(offer.creator, cAsset) >=
                    fullCTokenAmount,
                "lender balance"
            );

            uint256 protocolPremimuimInCtokens = ILiquidity(liquidityContractAddress)
                .assetAmountToCAssetAmount(offer.asset, protocolInterestAndPremium);

            address currentlender = loanAuction.lender;

            // update LoanAuction lender
            loanAuction.lender = offer.creator;

            ILiquidity(liquidityContractAddress).addToCAssetBalance(
                currentlender,
                cAsset,
                (fullCTokenAmount - protocolPremimuimInCtokens)
            );
            ILiquidity(liquidityContractAddress).withdrawCBalance(
                offer.creator,
                cAsset,
                fullCTokenAmount
            );
            ILiquidity(liquidityContractAddress).addToCAssetBalance(
                owner(),
                cAsset,
                protocolPremimuimInCtokens
            );
        }

        emit Refinance(
            offer.creator,
            offer.asset,
            loanAuction.nftOwner,
            offer.nftContractAddress,
            offer.nftId,
            offer
        );
    }

    /// @inheritdoc ILending
    function drawLoanAmount(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawAmount
    ) external whenNotPaused nonReentrant {
        LoanAuction storage loanAuction = getLoanAuctionInternal(nftContractAddress, nftId);

        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(loanAuction.asset);

        requireIsNotSanctioned(msg.sender);
        requireOpenLoan(loanAuction);
        requireNftOwner(loanAuction, msg.sender);
        requireDrawableAmount(loanAuction, drawAmount);
        requireLoanNotExpired(loanAuction);

        uint256 slashedDrawAmount = slashUnsupportedAmount(loanAuction, drawAmount, cAsset);

        if (slashedDrawAmount > 0) {
            uint128 currentAmountDrawn = loanAuction.amountDrawn;
            loanAuction.amountDrawn += SafeCastUpgradeable.toUint128(slashedDrawAmount);

            if (loanAuction.interestRatePerSecond > 0) {
                uint256 interestPerSecond = currentAmountDrawn / loanAuction.interestRatePerSecond;
                loanAuction.interestRatePerSecond =
                    SafeCastUpgradeable.toUint96(loanAuction.amountDrawn) /
                    SafeCastUpgradeable.toUint96(interestPerSecond);
            }

            if (loanAuction.protocolInterestRatePerSecond > 0) {
                uint256 protocolInterestPerSecond = currentAmountDrawn /
                    loanAuction.protocolInterestRatePerSecond;
                loanAuction.protocolInterestRatePerSecond =
                    SafeCastUpgradeable.toUint96(loanAuction.amountDrawn) /
                    SafeCastUpgradeable.toUint96(protocolInterestPerSecond);
            }

            uint256 cTokensBurnt = ILiquidity(liquidityContractAddress).burnCErc20(
                loanAuction.asset,
                slashedDrawAmount
            );

            ILiquidity(liquidityContractAddress).withdrawCBalance(
                loanAuction.lender,
                cAsset,
                cTokensBurnt
            );

            ILiquidity(liquidityContractAddress).sendValue(
                loanAuction.asset,
                slashedDrawAmount,
                loanAuction.nftOwner
            );
        }

        emit AmountDrawn(
            msg.sender,
            nftContractAddress,
            nftId,
            slashedDrawAmount,
            loanAuction.amountDrawn
        );
    }

    /// @dev Struct exists since we ran out of stack space in _repayLoan
    struct RepayLoanStruct {
        address nftContractAddress;
        uint256 nftId;
        bool repayFull;
        uint256 paymentAmount;
        bool checkMsgSender;
    }

    /// @inheritdoc ILending
    function repayLoan(address nftContractAddress, uint256 nftId)
        external
        payable
        override
        whenNotPaused
        nonReentrant
    {
        RepayLoanStruct memory rls = RepayLoanStruct({
            nftContractAddress: nftContractAddress,
            nftId: nftId,
            repayFull: true,
            paymentAmount: 0,
            checkMsgSender: true
        });
        _repayLoanAmount(rls);
    }

    /// @inheritdoc ILending
    function repayLoanForAccount(address nftContractAddress, uint256 nftId)
        external
        payable
        override
        whenNotPaused
        nonReentrant
    {
        RepayLoanStruct memory rls = RepayLoanStruct({
            nftContractAddress: nftContractAddress,
            nftId: nftId,
            repayFull: true,
            paymentAmount: 0,
            checkMsgSender: false
        });

        requireIsNotSanctioned(msg.sender);

        _repayLoanAmount(rls);
    }

    /// @inheritdoc ILending
    function partialRepayLoan(
        address nftContractAddress,
        uint256 nftId,
        uint256 amount
    ) external payable whenNotPaused nonReentrant {
        RepayLoanStruct memory rls = RepayLoanStruct({
            nftContractAddress: nftContractAddress,
            nftId: nftId,
            repayFull: false,
            paymentAmount: amount,
            checkMsgSender: true
        });

        _repayLoanAmount(rls);
    }

    function _repayLoanAmount(RepayLoanStruct memory rls) internal {
        LoanAuction storage loanAuction = getLoanAuctionInternal(rls.nftContractAddress, rls.nftId);
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(loanAuction.asset);

        requireIsNotSanctioned(msg.sender);

        if (!rls.repayFull) {
            if (loanAuction.asset == ETH_ADDRESS) {
                requireMsgValue(rls.paymentAmount);
            }
            require(rls.paymentAmount < loanAuction.amountDrawn, "use repayLoan");
        }

        requireOpenLoan(loanAuction);

        if (rls.checkMsgSender) {
            require(msg.sender == loanAuction.nftOwner, "msg.sender is not the borrower");
        }

        updateInterest(loanAuction);

        uint256 payment = rls.repayFull
            ? loanAuction.accumulatedLenderInterest +
                loanAuction.accumulatedProtocolInterest +
                loanAuction.amountDrawn
            : rls.paymentAmount;

        uint256 cTokensMinted = handleLoanPayment(rls, loanAuction, payment);

        payoutCTokenBalances(loanAuction, cAsset, cTokensMinted, payment);

        if (rls.repayFull) {
            transferNft(rls.nftContractAddress, rls.nftId, address(this), loanAuction.nftOwner);

            emit LoanRepaid(
                loanAuction.lender,
                loanAuction.nftOwner,
                rls.nftContractAddress,
                rls.nftId,
                loanAuction.asset,
                payment
            );

            delete _loanAuctions[rls.nftContractAddress][rls.nftId];
        } else {
            if (loanAuction.lenderRefi) {
                loanAuction.lenderRefi = false;
            }
            uint128 currentAmountDrawn = loanAuction.amountDrawn;
            loanAuction.amountDrawn -= SafeCastUpgradeable.toUint128(payment);

            if (loanAuction.interestRatePerSecond > 0) {
                uint256 interestPerSecond = currentAmountDrawn / loanAuction.interestRatePerSecond;
                loanAuction.interestRatePerSecond =
                    SafeCastUpgradeable.toUint96(loanAuction.amountDrawn) /
                    SafeCastUpgradeable.toUint96(interestPerSecond);
            }

            if (loanAuction.protocolInterestRatePerSecond > 0) {
                uint256 protocolInterestPerSecond = currentAmountDrawn /
                    loanAuction.protocolInterestRatePerSecond;
                loanAuction.protocolInterestRatePerSecond =
                    SafeCastUpgradeable.toUint96(loanAuction.amountDrawn) /
                    SafeCastUpgradeable.toUint96(protocolInterestPerSecond);
            }

            emit PartialRepayment(
                loanAuction.lender,
                loanAuction.nftOwner,
                rls.nftContractAddress,
                rls.nftId,
                loanAuction.asset,
                rls.paymentAmount
            );
        }
    }

    /// @inheritdoc ILending
    function seizeAsset(address nftContractAddress, uint256 nftId)
        external
        whenNotPaused
        nonReentrant
    {
        LoanAuction storage loanAuction = getLoanAuctionInternal(nftContractAddress, nftId);
        ILiquidity(liquidityContractAddress).getCAsset(loanAuction.asset); // Ensure asset mapping exists

        requireIsNotSanctioned(msg.sender);
        requireOpenLoan(loanAuction);
        requireLoanExpired(loanAuction);

        address currentLender = loanAuction.lender;
        address currentBorrower = loanAuction.nftOwner;

        delete _loanAuctions[nftContractAddress][nftId];

        transferNft(nftContractAddress, nftId, address(this), currentLender);

        emit AssetSeized(currentLender, currentBorrower, nftContractAddress, nftId);
    }

    function slashUnsupportedAmount(
        LoanAuction storage loanAuction,
        uint256 drawAmount,
        address cAsset
    ) internal returns (uint256) {
        if (loanAuction.lenderRefi) {
            loanAuction.lenderRefi = false;

            uint256 lenderBalance = ILiquidity(liquidityContractAddress).getCAssetBalance(
                loanAuction.lender,
                cAsset
            );

            uint256 drawTokens = ILiquidity(liquidityContractAddress).assetAmountToCAssetAmount(
                loanAuction.asset,
                drawAmount
            );

            if (lenderBalance < drawTokens) {
                uint256 lenderBalanceUnderlying = ILiquidity(liquidityContractAddress)
                    .cAssetAmountToAssetAmount(cAsset, lenderBalance);
                drawAmount = lenderBalanceUnderlying;

                // update interest only for protocol. This eliminates lender interest for the current interest period
                (, uint256 protocolInterest) = calculateInterestAccrued(loanAuction);

                loanAuction.accumulatedProtocolInterest += SafeCastUpgradeable.toUint128(
                    protocolInterest
                );

                loanAuction.lastUpdatedTimestamp = currentTimestamp();
                loanAuction.amount =
                    loanAuction.amountDrawn +
                    SafeCastUpgradeable.toUint128(drawAmount);
            }
        }

        return drawAmount;
    }

    /// @inheritdoc ILending
    function ownerOf(address nftContractAddress, uint256 nftId) public view returns (address) {
        return _loanAuctions[nftContractAddress][nftId].nftOwner;
    }

    function updateInterest(LoanAuction storage loanAuction)
        internal
        returns (uint256 lenderInterest, uint256 protocolInterest)
    {
        (lenderInterest, protocolInterest) = calculateInterestAccrued(loanAuction);

        loanAuction.accumulatedLenderInterest += SafeCastUpgradeable.toUint128(lenderInterest);
        loanAuction.accumulatedProtocolInterest += SafeCastUpgradeable.toUint128(protocolInterest);
        loanAuction.lastUpdatedTimestamp = currentTimestamp();
    }

    /// @inheritdoc ILending
    function calculateInterestAccrued(address nftContractAddress, uint256 nftId)
        public
        view
        returns (uint256, uint256)
    {
        return calculateInterestAccrued(getLoanAuctionInternal(nftContractAddress, nftId));
    }

    function calculateInterestAccrued(LoanAuction storage loanAuction)
        internal
        view
        returns (uint256 lenderInterest, uint256 protocolInterest)
    {
        uint256 timePassed = currentTimestamp() - loanAuction.lastUpdatedTimestamp;

        lenderInterest = (timePassed * loanAuction.interestRatePerSecond);
        protocolInterest = (timePassed * loanAuction.protocolInterestRatePerSecond);
    }

    /// @inheritdoc ILending
    function calculateLenderInterestPerSecond(
        uint128 amount,
        uint96 interestRateBps,
        uint32 duration
    ) public pure returns (uint96) {
        return
            (SafeCastUpgradeable.toUint96(amount) * SafeCastUpgradeable.toUint96(interestRateBps)) /
            SafeCastUpgradeable.toUint96(MAX_BPS) /
            SafeCastUpgradeable.toUint96(duration);
    }

    /// @inheritdoc ILending
    function calculateProtocolInterestPerSecond(uint128 amount, uint32 duration)
        public
        view
        returns (uint96)
    {
        return
            (SafeCastUpgradeable.toUint96(amount) *
                SafeCastUpgradeable.toUint96(protocolInterestBps)) /
            SafeCastUpgradeable.toUint96(MAX_BPS) /
            SafeCastUpgradeable.toUint96(duration);
    }

    /// @inheritdoc ILending
    function checkSufficientInterestAccumulated(address nftContractAddress, uint256 nftId)
        public
        view
        returns (
            bool,
            uint256,
            uint96
        )
    {
        return
            checkSufficientInterestAccumulated(getLoanAuctionInternal(nftContractAddress, nftId));
    }

    function checkSufficientInterestAccumulated(LoanAuction storage loanAuction)
        internal
        view
        returns (
            bool,
            uint256,
            uint96
        )
    {
        (uint256 lenderInterest, ) = calculateInterestAccrued(loanAuction);

        uint96 interestThreshold = (SafeCastUpgradeable.toUint96(loanAuction.amountDrawn) *
            SafeCastUpgradeable.toUint96(gasGriefingPremiumBps)) /
            SafeCastUpgradeable.toUint96(MAX_BPS);

        return (
            lenderInterest > interestThreshold ? true : false,
            lenderInterest,
            interestThreshold
        );
    }

    /// @inheritdoc ILending
    function checkSufficientTerms(
        address nftContractAddress,
        uint256 nftId,
        uint128 amount,
        uint96 interestRatePerSecond,
        uint32 duration
    ) public view returns (bool) {
        return
            checkSufficientTerms(
                getLoanAuctionInternal(nftContractAddress, nftId),
                amount,
                interestRatePerSecond,
                duration
            );
    }

    function checkSufficientTerms(
        LoanAuction storage loanAuction,
        uint128 amount,
        uint96 interestRatePerSecond,
        uint32 duration
    ) internal view returns (bool) {
        uint256 loanDuration = loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp;

        // calculate the Bps improvement of each offer term
        uint256 amountImprovement = ((amount - loanAuction.amount) * MAX_BPS) / loanAuction.amount;
        uint256 interestImprovement = ((loanAuction.interestRatePerSecond - interestRatePerSecond) *
            MAX_BPS) / loanAuction.interestRatePerSecond;
        uint256 durationImprovement = ((duration - loanDuration) * MAX_BPS) / loanDuration;

        // sum improvements
        uint256 improvementSum = amountImprovement + interestImprovement + durationImprovement;

        // check and return if improvements are greater than 25 bps total
        return improvementSum > termGriefingPremiumBps ? true : false;
    }

    function requireSignature65(bytes memory signature) internal pure {
        require(signature.length == 65, "signature unsupported");
    }

    function requireOfferPresent(Offer memory offer) internal pure {
        require(offer.asset != address(0), "no offer");
    }

    function requireOfferAmount(Offer memory offer, uint256 amount) internal pure {
        require(offer.amount >= amount, "offer amount");
    }

    function requireNoOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.lastUpdatedTimestamp == 0, "Loan already open");
    }

    function requireOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.lastUpdatedTimestamp != 0, "loan not active");
    }

    function requireLoanExpired(LoanAuction storage loanAuction) internal view {
        require(currentTimestamp() >= loanAuction.loanEndTimestamp, "loan not expired");
    }

    function requireLoanNotExpired(LoanAuction storage loanAuction) internal view {
        require(currentTimestamp() < loanAuction.loanEndTimestamp, "loan expired");
    }

    function requireOfferNotExpired(Offer memory offer) internal view {
        require(offer.expiration > currentTimestamp(), "offer expired");
    }

    function requireMinDurationForOffer(Offer memory offer) internal pure {
        require(offer.duration >= 1 days, "offer duration");
    }

    function requireLenderOffer(Offer memory offer) internal pure {
        require(offer.lenderOffer, "lender offer");
    }

    function requireBorrowerOffer(Offer memory offer) internal pure {
        require(!offer.lenderOffer, "borrower offer");
    }

    function requireNoFloorTerms(Offer memory offer) internal pure {
        require(!offer.floorTerm, "floor term");
    }

    function requireNoFixedTerm(LoanAuction storage loanAuction) internal view {
        require(!loanAuction.fixedTerms, "fixed term loan");
    }

    function requireNoFixTermOffer(Offer memory offer) internal pure {
        require(!offer.fixedTerms, "fixed term offer");
    }

    function requireIsNotSanctioned(address addressToCheck) internal view {
        SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
        bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
        require(!isToSanctioned, "sanctioned address");
    }

    function require721Owner(
        address nftContractAddress,
        uint256 nftId,
        address owner
    ) internal view {
        require(IERC721Upgradeable(nftContractAddress).ownerOf(nftId) == owner, "nft owner");
    }

    function requireMatchingAsset(address asset1, address asset2) internal pure {
        require(asset1 == asset2, "asset mismatch");
    }

    function requireDrawableAmount(LoanAuction storage loanAuction, uint256 drawAmount)
        internal
        view
    {
        require((drawAmount + loanAuction.amountDrawn) <= loanAuction.amount, "funds overdrawn");
    }

    function requireNftOwner(LoanAuction storage loanAuction, address nftOwner) internal view {
        require(nftOwner == loanAuction.nftOwner, "nft owner");
    }

    function requireMatchingNftId(Offer memory offer, uint256 nftId) internal pure {
        require(nftId == offer.nftId, "offer nftId mismatch");
    }

    function requireMsgValue(uint256 amount) internal view {
        require(amount == msg.value, "msg value");
    }

    function requireOfferCreator(Offer memory offer, address creator) internal pure {
        require(creator == offer.creator, "offer creator mismatch");
    }

    function requireOfferParity(LoanAuction storage loanAuction, Offer memory offer) internal view {
        // Caching fields here for gas usage
        uint256 amount = loanAuction.amount;
        uint256 interestRatePerSecond = loanAuction.interestRatePerSecond;
        uint256 loanEndTime = loanAuction.loanEndTimestamp;
        uint256 offerEndTime = loanAuction.loanBeginTimestamp + offer.duration;

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

        revert("not an improvement");
    }

    function createLoan(
        LoanAuction storage loanAuction,
        Offer memory offer,
        address lender,
        address borrower
    ) internal {
        loanAuction.nftOwner = borrower;
        loanAuction.lender = lender;
        loanAuction.asset = offer.asset;
        loanAuction.amount = offer.amount;
        loanAuction.loanEndTimestamp = currentTimestamp() + offer.duration;
        loanAuction.loanBeginTimestamp = currentTimestamp();
        loanAuction.lastUpdatedTimestamp = currentTimestamp();
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;
        loanAuction.interestRatePerSecond = offer.interestRatePerSecond;

        uint96 protocolInterestRatePerSecond = calculateProtocolInterestPerSecond(
            offer.amount,
            offer.duration
        );

        loanAuction.protocolInterestRatePerSecond = protocolInterestRatePerSecond;
    }

    function transferNft(
        address nftContractAddress,
        uint256 nftId,
        address from,
        address to
    ) internal {
        IERC721Upgradeable(nftContractAddress).safeTransferFrom(from, to, nftId);
    }

    function payoutCTokenBalances(
        LoanAuction storage loanAuction,
        address cAsset,
        uint256 totalCTokens,
        uint256 totalPayment
    ) internal {
        uint256 cTokensToLender = (totalCTokens *
            (loanAuction.amountDrawn + loanAuction.accumulatedLenderInterest)) / totalPayment;
        uint256 cTokensToProtocol = (totalCTokens * loanAuction.accumulatedProtocolInterest) /
            totalPayment;

        ILiquidity(liquidityContractAddress).addToCAssetBalance(
            loanAuction.lender,
            cAsset,
            cTokensToLender
        );
        ILiquidity(liquidityContractAddress).addToCAssetBalance(owner(), cAsset, cTokensToProtocol);
    }

    function handleLoanPayment(
        RepayLoanStruct memory rls,
        LoanAuction storage loanAuction,
        uint256 payment
    ) internal returns (uint256) {
        if (loanAuction.asset == ETH_ADDRESS) {
            if (rls.repayFull) {
                require(msg.value >= payment, "msg.value too low");
            }

            payable(address(liquidityContractAddress)).sendValue(payment);
            uint256 cTokensMinted = ILiquidity(liquidityContractAddress).mintCEth(payment);

            // If the caller has overpaid we send the extra ETH back
            if (payment < msg.value) {
                payable(msg.sender).sendValue(msg.value - payment);
            }
            return cTokensMinted;
        } else {
            return
                ILiquidity(liquidityContractAddress).mintCErc20(
                    msg.sender,
                    liquidityContractAddress,
                    loanAuction.asset,
                    payment
                );
        }
    }

    function currentTimestamp() internal view returns (uint32) {
        return SafeCastUpgradeable.toUint32(block.timestamp);
    }

    // solhint-disable-next-line no-empty-blocks
    function renounceOwnership() public override onlyOwner {}
}
