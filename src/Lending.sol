//SPDX-License-Identifier: MIT
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

/// @title NiftyApes Lending
/// @custom:version 1.0
/// @author captnseagraves (captnseagraves.eth)
/// @custom:contributor dankurka
/// @custom:contributor 0xAlcibiades (alcibiades.eth)
/// @custom:contributor zjmiller (zjmiller.eth)

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

    /// @dev Internal constant address for the Chainalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    /// @notice The maximum value that any fee on the protocol can be set to.
    ///         Fees on the protocol are denominated in parts of 10_000.
    uint256 private constant MAX_FEE = 1_000;

    /// @notice The base value for fees in the protocol.
    uint256 private constant MAX_BPS = 10_000;

    /// @dev A mapping for a NFT to a loan auction.
    ///      The mapping has to be broken into two parts since an NFT is denominated by its address (first part)
    ///      and its nftId (second part) in our code base.
    mapping(address => mapping(uint256 => LoanAuction)) private _loanAuctions;

    /// @inheritdoc ILending
    address public offersContractAddress;

    /// @inheritdoc ILending
    address public liquidityContractAddress;

    /// @inheritdoc ILending
    address public sigLendingContractAddress;

    /// @inheritdoc ILending
    address public flashClaimContractAddress;

    /// @inheritdoc ILending
    address public flashPurchaseContractAddress;

    /// @inheritdoc ILending
    address public flashSellContractAddress;

    /// @inheritdoc ILending
    address public sellOnSeaportContractAddress;

    /// @inheritdoc ILending
    uint16 public protocolInterestBps;

    /// @inheritdoc ILending
    uint16 public originationPremiumBps;

    /// @inheritdoc ILending
    uint16 public gasGriefingPremiumBps;

    /// @inheritdoc ILending
    uint16 public termGriefingPremiumBps;

    /// @inheritdoc ILending
    uint16 public defaultRefinancePremiumBps;

    /// @dev The status of sanctions checks. Can be set to false if oracle becomes malicious.
    bool internal _sanctionsPause;

    // Mapping owner to nftContractAddress to token count
    mapping(address => mapping(address => uint256)) private _balances;

    // Mapping from owner to nftContractAddress to list of owned token IDs
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _ownedTokens;

    // Mapping from nftContractAddress to token ID to index of the owner tokens list
    mapping(address => mapping(uint256 => uint256)) private _ownedTokensIndex;

    /// @inheritdoc ILending
    address public refinanceContractAddress;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[496] private __gap;

    /// @notice The initializer for the NiftyApes protocol.
    ///         Nifty Apes is intended to be deployed behind a proxy amd thus needs to initialize
    ///         its state outsize of a constructor.
    function initialize(
        address newLiquidityContractAddress,
        address newOffersContractAddress,
        address newSigLendingContractAddress,
        address newRefinanceContractAddress,
        address newFlashClaimContractAddress,
        address newFlashPurchaseAddress,
        address newFlashSellContractAddress,
        address newSellOnSeaportContractAddress
    ) public initializer {
        protocolInterestBps = 0;
        originationPremiumBps = 25;
        gasGriefingPremiumBps = 25;
        termGriefingPremiumBps = 25;
        defaultRefinancePremiumBps = 25;

        liquidityContractAddress = newLiquidityContractAddress;
        offersContractAddress = newOffersContractAddress;
        sigLendingContractAddress = newSigLendingContractAddress;
        refinanceContractAddress = newRefinanceContractAddress;
        flashClaimContractAddress = newFlashClaimContractAddress;
        flashPurchaseContractAddress = newFlashPurchaseAddress;
        flashSellContractAddress = newFlashSellContractAddress;
        sellOnSeaportContractAddress = newSellOnSeaportContractAddress;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }

    /// @inheritdoc ILendingAdmin
    function updateProtocolInterestBps(uint16 newProtocolInterestBps) external onlyOwner {
        _requireMaxFee(newProtocolInterestBps);
        emit ProtocolInterestBpsUpdated(protocolInterestBps, newProtocolInterestBps);
        protocolInterestBps = newProtocolInterestBps;
    }

    /// @inheritdoc ILendingAdmin
    function updateOriginationPremiumLenderBps(uint16 newOriginationPremiumBps) external onlyOwner {
        _requireMaxFee(newOriginationPremiumBps);
        emit OriginationPremiumBpsUpdated(originationPremiumBps, newOriginationPremiumBps);
        originationPremiumBps = newOriginationPremiumBps;
    }

    /// @inheritdoc ILendingAdmin
    function updateGasGriefingPremiumBps(uint16 newGasGriefingPremiumBps) external onlyOwner {
        _requireMaxFee(newGasGriefingPremiumBps);
        emit GasGriefingPremiumBpsUpdated(gasGriefingPremiumBps, newGasGriefingPremiumBps);
        gasGriefingPremiumBps = newGasGriefingPremiumBps;
    }

    /// @inheritdoc ILendingAdmin
    function updateDefaultRefinancePremiumBps(uint16 newDefaultRefinancePremiumBps)
        external
        onlyOwner
    {
        _requireMaxFee(newDefaultRefinancePremiumBps);
        emit DefaultRefinancePremiumBpsUpdated(
            defaultRefinancePremiumBps,
            newDefaultRefinancePremiumBps
        );
        defaultRefinancePremiumBps = newDefaultRefinancePremiumBps;
    }

    /// @inheritdoc ILendingAdmin
    function updateTermGriefingPremiumBps(uint16 newTermGriefingPremiumBps) external onlyOwner {
        _requireMaxFee(newTermGriefingPremiumBps);
        emit TermGriefingPremiumBpsUpdated(termGriefingPremiumBps, newTermGriefingPremiumBps);
        termGriefingPremiumBps = newTermGriefingPremiumBps;
    }

    /// @inheritdoc ILendingAdmin
    function pauseSanctions() external onlyOwner {
        _sanctionsPause = true;
        emit LendingSanctionsPaused();
    }

    /// @inheritdoc ILendingAdmin
    function unpauseSanctions() external onlyOwner {
        _sanctionsPause = false;
        emit LendingSanctionsUnpaused();
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
        return _getLoanAuctionInternal(nftContractAddress, nftId);
    }

    function _getLoanAuctionInternal(address nftContractAddress, uint256 nftId)
        internal
        view
        returns (LoanAuction storage)
    {
        return _loanAuctions[nftContractAddress][nftId];
    }

    /// @inheritdoc ILending
    function updateLoanAuctionInternal(address nftContractAddress, uint256 nftId, LoanAuction memory newLoanAuction)
        external
    {
        _requireRefinanceContract();
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];

        loanAuction.nftOwner = newLoanAuction.nftOwner;
        loanAuction.lender = newLoanAuction.lender;
        loanAuction.asset = newLoanAuction.asset;
        loanAuction.amount = newLoanAuction.amount;
        loanAuction.loanEndTimestamp = newLoanAuction.loanEndTimestamp;
        loanAuction.loanBeginTimestamp = newLoanAuction.loanBeginTimestamp;
        loanAuction.lastUpdatedTimestamp = newLoanAuction.lastUpdatedTimestamp;
        loanAuction.amountDrawn = newLoanAuction.amountDrawn;
        loanAuction.fixedTerms = newLoanAuction.fixedTerms;
        loanAuction.lenderRefi = newLoanAuction.lenderRefi;
        loanAuction.accumulatedLenderInterest = newLoanAuction.accumulatedLenderInterest;
        loanAuction.accumulatedPaidProtocolInterest = newLoanAuction.accumulatedPaidProtocolInterest;
        loanAuction.interestRatePerSecond = newLoanAuction.interestRatePerSecond;
        loanAuction.protocolInterestRatePerSecond = newLoanAuction.protocolInterestRatePerSecond;
        loanAuction.slashableLenderInterest = newLoanAuction.slashableLenderInterest;
        loanAuction.unpaidProtocolInterest = newLoanAuction.unpaidProtocolInterest;
    }

    function emitAmountDrawnInternal(
        address nftContractAddress,
        uint256 nftId,
        uint256 slashedDrawAmount,
        LoanAuction memory loanAuction
    ) external {
        emit AmountDrawn(nftContractAddress, nftId, slashedDrawAmount, loanAuction);
    }

    /// @inheritdoc ILending
    function executeLoanByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external payable whenNotPaused nonReentrant {
        Offer memory offer = _offerNftIdAndCountChecks(
            nftContractAddress,
            nftId,
            floorTerm,
            offerHash
        );

        _requireLenderOffer(offer);
        _doExecuteLoan(offer, offer.creator, msg.sender, nftId);
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

        _requireBorrowerOffer(offer);
        _requireNoFloorTerms(offer);

        IOffers(offersContractAddress).removeOffer(nftContractAddress, nftId, offerHash, floorTerm);

        _doExecuteLoan(offer, msg.sender, offer.creator, nftId);
    }

    function doExecuteLoan(
        Offer memory offer,
        address lender,
        address borrower,
        uint256 nftId
    ) external whenNotPaused nonReentrant {
        _requireSigLendingContract();
        _doExecuteLoan(offer, lender, borrower, nftId);
    }

    function _doExecuteLoan(
        Offer memory offer,
        address lender,
        address borrower,
        uint256 nftId
    ) internal {
        _requireIsNotSanctioned(lender);
        _requireIsNotSanctioned(borrower);
        // requireOfferPresent
        require(offer.asset != address(0), "00004");

        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);

        LoanAuction storage loanAuction = _getLoanAuctionInternal(offer.nftContractAddress, nftId);

        // requireNoOpenLoan
        require(loanAuction.lastUpdatedTimestamp == 0, "00006");
        _requireOfferNotExpired(offer);
        _requireMinDurationForOffer(offer);
        // require721Owner
        require(IERC721Upgradeable(offer.nftContractAddress).ownerOf(nftId) == borrower, "00018");

        _createLoan(loanAuction, offer, lender, borrower);

        _transferNft(offer.nftContractAddress, nftId, borrower, address(this));

        _addTokenToOwnerEnumeration(borrower, offer.nftContractAddress, nftId);

        uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
            offer.asset,
            offer.amount
        );
        ILiquidity(liquidityContractAddress).withdrawCBalance(lender, cAsset, cTokensBurned);

        ILiquidity(liquidityContractAddress).sendValue(offer.asset, offer.amount, borrower);

        emit LoanExecuted(offer.nftContractAddress, nftId, loanAuction);
    }

    /// @inheritdoc ILending
    function drawLoanAmount(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawAmount
    ) external whenNotPaused nonReentrant {
        LoanAuction storage loanAuction = _getLoanAuctionInternal(nftContractAddress, nftId);

        _requireIsNotSanctioned(loanAuction.lender);
        _requireIsNotSanctioned(msg.sender);
        _requireOpenLoan(loanAuction);
        _requireNftOwner(loanAuction, msg.sender);
        // requireDrawableAmount
        require((drawAmount + loanAuction.amountDrawn) <= loanAuction.amount, "00020");
        _requireLoanNotExpired(loanAuction);

        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(loanAuction.asset);

        _updateInterest(loanAuction);

        uint256 slashedDrawAmount = _slashUnsupportedAmount(loanAuction, drawAmount, cAsset);

        if (slashedDrawAmount != 0) {
            uint256 currentAmountDrawn = loanAuction.amountDrawn;
            loanAuction.amountDrawn += SafeCastUpgradeable.toUint128(slashedDrawAmount);

            uint32 duration = (loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp);

            if (loanAuction.interestRatePerSecond != 0) {
                uint256 interestBps = _calculateInterestBps(
                    currentAmountDrawn,
                    loanAuction.interestRatePerSecond,
                    duration
                );
                loanAuction.interestRatePerSecond = calculateInterestPerSecond(
                    loanAuction.amountDrawn,
                    interestBps,
                    duration
                );
            }

            if (loanAuction.protocolInterestRatePerSecond != 0) {
                loanAuction.protocolInterestRatePerSecond = calculateInterestPerSecond(
                    loanAuction.amountDrawn,
                    protocolInterestBps,
                    duration
                );
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

        emit AmountDrawn(nftContractAddress, nftId, slashedDrawAmount, loanAuction);
    }

    /// @inheritdoc ILending
    function repayLoan(address nftContractAddress, uint256 nftId)
        external
        payable
        override
        whenNotPaused
        nonReentrant
    {
        LoanAuction memory loanAuction = _getLoanAuctionInternal(nftContractAddress, nftId);
        address nftOwner = loanAuction.nftOwner;
        _repayLoanAmount(nftContractAddress, nftId, true, 0, true);
        _transferNft(nftContractAddress, nftId, address(this), nftOwner);
    }

    /// @inheritdoc ILending
    function repayLoanForAccount(
        address nftContractAddress,
        uint256 nftId,
        uint32 expectedLoanBeginTimestamp
    ) external payable override whenNotPaused nonReentrant {
        LoanAuction memory loanAuction = _getLoanAuctionInternal(nftContractAddress, nftId);
        // requireExpectedLoanIsActive
        require(loanAuction.loanBeginTimestamp == expectedLoanBeginTimestamp, "00027");
        _requireIsNotSanctioned(msg.sender);

        address nftOwner = loanAuction.nftOwner;
        _repayLoanAmount(nftContractAddress, nftId, true, 0, false);
        _transferNft(nftContractAddress, nftId, address(this), nftOwner);
    }

    /// @inheritdoc ILending
    function repayLoanForAccountInternal(
        address nftContractAddress,
        uint256 nftId,
        uint32 expectedLoanBeginTimestamp
    ) external payable override whenNotPaused nonReentrant {
        _requireExpectedContract();
        LoanAuction memory loanAuction = _getLoanAuctionInternal(nftContractAddress, nftId);
        // requireExpectedLoanIsActive
        require(loanAuction.loanBeginTimestamp == expectedLoanBeginTimestamp, "00027");
        _repayLoanAmount(nftContractAddress, nftId, true, 0, false);
    }

    /// @inheritdoc ILending
    function partialRepayLoan(
        address nftContractAddress,
        uint256 nftId,
        uint256 amount
    ) external payable whenNotPaused nonReentrant {
        _repayLoanAmount(nftContractAddress, nftId, false, amount, true);
    }

    function _repayLoanAmount(
        address nftContractAddress,
        uint256 nftId,
        bool repayFull,
        uint256 paymentAmount,
        bool checkMsgSender
    ) internal {
        LoanAuction storage loanAuction = _getLoanAuctionInternal(nftContractAddress, nftId);

        _requireIsNotSanctioned(loanAuction.nftOwner);
        _requireOpenLoan(loanAuction);

        if (checkMsgSender) {
            require(msg.sender == loanAuction.nftOwner, "00028");
        }

        if (loanAuction.loanEndTimestamp - 1 days > _currentTimestamp32()) {
            uint256 interestThresholdDelta = _checkSufficientInterestAccumulated(loanAuction);

            if (interestThresholdDelta > 0) {
                loanAuction.accumulatedLenderInterest += SafeCastUpgradeable.toUint128(
                    interestThresholdDelta
                );
            }
        }

        _updateInterest(loanAuction);

        if (repayFull) {
            paymentAmount =
                uint256(loanAuction.accumulatedLenderInterest) +
                loanAuction.accumulatedPaidProtocolInterest +
                loanAuction.unpaidProtocolInterest +
                loanAuction.slashableLenderInterest +
                loanAuction.amountDrawn;
        } else {
            require(paymentAmount < loanAuction.amountDrawn, "00029");
            _requireLoanNotExpired(loanAuction);
        }
        if (loanAuction.asset == ETH_ADDRESS) {
            require(msg.value >= paymentAmount, "00030");
            // If the caller has overpaid we send the extra ETH back
            if (msg.value > paymentAmount) {
                unchecked {
                    payable(msg.sender).sendValue(msg.value - paymentAmount);
                }
            }
        }

        uint256 cTokensMinted = _handleLoanPayment(loanAuction.asset, paymentAmount);

        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(loanAuction.asset);

        _payoutCTokenBalances(loanAuction, cAsset, cTokensMinted, paymentAmount, repayFull);

        if (repayFull) {
            _removeTokenFromOwnerEnumeration(loanAuction.nftOwner, nftContractAddress, nftId);
            emit LoanRepaid(nftContractAddress, nftId, paymentAmount, loanAuction);

            delete _loanAuctions[nftContractAddress][nftId];
        } else {
            if (loanAuction.lenderRefi) {
                loanAuction.lenderRefi = false;
                if (loanAuction.slashableLenderInterest > 0) {
                    loanAuction.accumulatedLenderInterest += loanAuction.slashableLenderInterest;
                    loanAuction.slashableLenderInterest = 0;
                }
            }
            uint256 currentAmountDrawn = loanAuction.amountDrawn;
            loanAuction.amountDrawn -= SafeCastUpgradeable.toUint128(paymentAmount);

            uint32 duration = (loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp);

            if (loanAuction.interestRatePerSecond != 0) {
                uint256 interestBps = _calculateInterestBps(
                    currentAmountDrawn,
                    loanAuction.interestRatePerSecond,
                    duration
                );
                loanAuction.interestRatePerSecond = calculateInterestPerSecond(
                    loanAuction.amountDrawn,
                    interestBps,
                    duration
                );
            }

            if (loanAuction.protocolInterestRatePerSecond != 0) {
                loanAuction.protocolInterestRatePerSecond = calculateInterestPerSecond(
                    loanAuction.amountDrawn,
                    protocolInterestBps,
                    duration
                );
            }

            emit PartialRepayment(nftContractAddress, nftId, paymentAmount, loanAuction);
        }
    }

    /// @inheritdoc ILending
    function seizeAsset(address nftContractAddress, uint256 nftId)
        external
        whenNotPaused
        nonReentrant
    {
        LoanAuction storage loanAuction = _getLoanAuctionInternal(nftContractAddress, nftId);
        ILiquidity(liquidityContractAddress).getCAsset(loanAuction.asset); // Ensure asset mapping exists

        _requireIsNotSanctioned(loanAuction.lender);
        _requireOpenLoan(loanAuction);
        // requireLoanExpired
        require(_currentTimestamp32() >= loanAuction.loanEndTimestamp, "00008");

        address currentLender = loanAuction.lender;
        address nftOwner = loanAuction.nftOwner;
        emit AssetSeized(nftContractAddress, nftId, loanAuction);

        delete _loanAuctions[nftContractAddress][nftId];

        _transferNft(nftContractAddress, nftId, address(this), currentLender);
        _removeTokenFromOwnerEnumeration(nftOwner, nftContractAddress, nftId);
    }

    /// @inheritdoc ILending
    function ownerOf(address nftContractAddress, uint256 nftId) public view returns (address) {
        return _loanAuctions[nftContractAddress][nftId].nftOwner;
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

    function _slashUnsupportedAmount(
        LoanAuction storage loanAuction,
        uint256 drawAmount,
        address cAsset
    ) internal returns (uint256) {
        uint256 lenderBalance = ILiquidity(liquidityContractAddress).getCAssetBalance(
            loanAuction.lender,
            cAsset
        );

        uint256 drawTokens = ILiquidity(liquidityContractAddress).assetAmountToCAssetAmount(
            loanAuction.asset,
            drawAmount
        );

        if (lenderBalance < drawTokens) {
            drawAmount = ILiquidity(liquidityContractAddress).cAssetAmountToAssetAmount(
                cAsset,
                lenderBalance
            );

            loanAuction.amount = SafeCastUpgradeable.toUint128(
                loanAuction.amountDrawn + drawAmount
            );
        }

        if (loanAuction.lenderRefi) {
            loanAuction.lenderRefi = false;

            if (lenderBalance < drawTokens) {
                // This eliminates all accumulated interest/profit for this lender on the loan
                loanAuction.slashableLenderInterest = 0;
            }
        }

        if (loanAuction.slashableLenderInterest > 0) {
            loanAuction.accumulatedLenderInterest += loanAuction.slashableLenderInterest;
            loanAuction.slashableLenderInterest = 0;
        }

        return drawAmount;
    }

    function _updateInterest(LoanAuction storage loanAuction)
        internal
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

    /// @inheritdoc ILending
    function calculateInterestAccrued(address nftContractAddress, uint256 nftId)
        public
        view
        returns (uint256, uint256)
    {
        return _calculateInterestAccrued(_getLoanAuctionInternal(nftContractAddress, nftId));
    }

    function _calculateInterestAccrued(LoanAuction storage loanAuction)
        internal
        view
        returns (uint256 lenderInterest, uint256 protocolInterest)
    {
        uint256 timePassed = _currentTimestamp32() - loanAuction.lastUpdatedTimestamp;

        lenderInterest = (timePassed * loanAuction.interestRatePerSecond);
        protocolInterest = (timePassed * loanAuction.protocolInterestRatePerSecond);
    }

    /// @inheritdoc ILending
    function calculateInterestPerSecond(
        uint256 amount,
        uint256 interestBps,
        uint256 duration
    ) public pure returns (uint96) {
        // account for 0 protocolInterestBps
        if (interestBps == 0) {
            return 0;
        }

        uint96 result = SafeCastUpgradeable.toUint96((amount * interestBps) / MAX_BPS / duration);

        // return 1 for cases where (amount * interestBps) / MAX_BPS < duration;
        return result == 0 ? 1 : result;
    }

    function _calculateInterestBps(
        uint256 amount,
        uint96 interestRatePerSecond,
        uint256 duration
    ) private pure returns (uint256) {
        return (((uint256(interestRatePerSecond) * duration) * MAX_BPS) / amount) + 1;
    }

    /// @inheritdoc ILending
    function checkSufficientInterestAccumulated(address nftContractAddress, uint256 nftId)
        public
        view
        returns (uint256)
    {
        return
            _checkSufficientInterestAccumulated(_getLoanAuctionInternal(nftContractAddress, nftId));
    }

    function _checkSufficientInterestAccumulated(LoanAuction storage loanAuction)
        internal
        view
        returns (uint256 interestThresholdDelta)
    {
        (uint256 lenderInterest, ) = _calculateInterestAccrued(loanAuction);

        uint256 interestThreshold = (uint256(loanAuction.amountDrawn) * gasGriefingPremiumBps) /
            MAX_BPS;

        if (interestThreshold > lenderInterest) {
            return interestThreshold - lenderInterest;
        } else {
            return 0;
        }
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
            _checkSufficientTerms(
                _getLoanAuctionInternal(nftContractAddress, nftId),
                amount,
                interestRatePerSecond,
                duration
            );
    }

    function _checkSufficientTerms(
        LoanAuction storage loanAuction,
        uint128 amount,
        uint96 interestRatePerSecond,
        uint32 duration
    ) internal view returns (bool) {
        uint256 loanDuration = loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp;

        // calculate the Bps improvement of each offer term
        uint256 amountImprovement = ((uint256(amount) - loanAuction.amount) * MAX_BPS) /
            loanAuction.amount;
        uint256 interestImprovement = ((uint256(loanAuction.interestRatePerSecond) -
            interestRatePerSecond) * MAX_BPS) / loanAuction.interestRatePerSecond;
        uint256 durationImprovement = ((uint256(duration) - loanDuration) * MAX_BPS) / loanDuration;

        // sum improvements
        uint256 improvementSum = amountImprovement + interestImprovement + durationImprovement;

        // check and return if improvements are greater than 25 bps total
        return improvementSum > termGriefingPremiumBps;
    }

    /// @inheritdoc ILending
    function validateSeaportOrderSellOnSeaport(address seaportContractAddress, ISeaport.Order[] memory orders) external {
        _requireSellOnSeaportContract();
        ISeaport(seaportContractAddress).validate(orders);
    }

    /// @inheritdoc ILending
    function cancelOrderSellOnSeaport(address seaportContractAddress, ISeaport.OrderComponents[] memory orderComponentsList) external returns (bool) {
        _requireSellOnSeaportContract();
        return ISeaport(seaportContractAddress).cancel(orderComponentsList);
    }

    /// @inheritdoc ILending
    function balanceOf(address owner, address nftContractAddress) public view override returns (uint256) {
        require(owner != address(0), "00035");
        return _balances[owner][nftContractAddress];
    }

    /// @inheritdoc ILending
    function tokenOfOwnerByIndex(address owner, address nftContractAddress, uint256 index) public view override returns (uint256) {
        require(index < balanceOf(owner, nftContractAddress), "00069");
        return _ownedTokens[owner][nftContractAddress][index];
    }

    /// @dev Private function to add a token to this extension's ownership-tracking data structures.
    /// @param owner address representing the new owner of the given token ID
    /// @param nftContractAddress address nft collection address
    /// @param tokenId uint256 ID of the token to be added to the tokens list of the given address
    function _addTokenToOwnerEnumeration(address owner, address nftContractAddress, uint256 tokenId) private {
        uint256 length = _balances[owner][nftContractAddress];
        _ownedTokens[owner][nftContractAddress][length] = tokenId;
        _ownedTokensIndex[nftContractAddress][tokenId] = length;
        _balances[owner][nftContractAddress] += 1;
    }

    /// @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
    /// while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
    /// gas optimizations e.g. when performing a transfer operation (avoiding double writes).
    /// This has O(1) time complexity, but alters the order of the _ownedTokens array.
    /// @param owner address representing the owner of the given token ID to be removed
    /// @param nftContractAddress address nft collection address
    /// @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
    function _removeTokenFromOwnerEnumeration(address owner, address nftContractAddress, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and then delete the last slot (swap and pop).

        uint256 lastTokenIndex = balanceOf(owner, nftContractAddress) - 1;
        uint256 tokenIndex = _ownedTokensIndex[nftContractAddress][tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[owner][nftContractAddress][lastTokenIndex];

            _ownedTokens[owner][nftContractAddress][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[nftContractAddress][lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[nftContractAddress][tokenId];
        delete _ownedTokens[owner][nftContractAddress][lastTokenIndex];

        // decrease the owner's collection balance by one
        _balances[owner][nftContractAddress] -= 1;
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

    function _requireMaxFee(uint16 feeValue) internal pure {
        require(feeValue <= MAX_FEE, "00002");
    }

    function _requireOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.lastUpdatedTimestamp != 0, "00007");
    }

    function _requireLoanNotExpired(LoanAuction storage loanAuction) internal view {
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

    function _requireBorrowerOffer(Offer memory offer) internal pure {
        require(!offer.lenderOffer, "00013");
    }

    function _requireNoFloorTerms(Offer memory offer) internal pure {
        require(!offer.floorTerm, "00014");
    }

    function _requireNoFixedTerm(LoanAuction storage loanAuction) internal view {
        require(!loanAuction.fixedTerms, "00015");
    }

    function _requireIsNotSanctioned(address addressToCheck) internal view {
        if (!_sanctionsPause) {
            SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
            bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
            require(!isToSanctioned, "00017");
        }
    }

    function _requireMatchingAsset(address asset1, address asset2) internal pure {
        require(asset1 == asset2, "00019");
    }

    function _requireNftOwner(LoanAuction storage loanAuction, address nftOwner) internal view {
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

    function _requireExpectedContract() internal view {
        require(
            msg.sender == flashClaimContractAddress || msg.sender == flashSellContractAddress || msg.sender == sellOnSeaportContractAddress,
            "00031"
        );
    }

    function  _requireSellOnSeaportContract() internal view {
        require(msg.sender == sellOnSeaportContractAddress, "00031");
    }

    function _requireFlashPurchaseContract() internal view {
        require(msg.sender == flashPurchaseContractAddress, "00031");
    }

    function _requireRefinanceContract() internal view {
        require(msg.sender == refinanceContractAddress, "00031");
    }

    function _requireOfferParity(LoanAuction storage loanAuction, Offer memory offer)
        internal
        view
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

    /// @inheritdoc ILending
    function createLoanFlashPurchase(
        Offer memory offer,
        uint256 nftId,
        address lender,
        address borrower
    ) external {
        LoanAuction storage loanAuction = _getLoanAuctionInternal(offer.nftContractAddress, nftId);
        _requireFlashPurchaseContract();
        _createLoan(loanAuction, offer, lender, borrower);
    }

    function _createLoan(
        LoanAuction storage loanAuction,
        Offer memory offer,
        address lender,
        address borrower
    ) internal {
        loanAuction.nftOwner = borrower;
        loanAuction.lender = lender;
        loanAuction.asset = offer.asset;
        loanAuction.amount = offer.amount;
        loanAuction.loanEndTimestamp = _currentTimestamp32() + offer.duration;
        loanAuction.loanBeginTimestamp = _currentTimestamp32();
        loanAuction.lastUpdatedTimestamp = _currentTimestamp32();
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;
        loanAuction.lenderRefi = false;
        loanAuction.accumulatedLenderInterest = 0;
        loanAuction.accumulatedPaidProtocolInterest = 0;
        loanAuction.interestRatePerSecond = offer.interestRatePerSecond;
        loanAuction.protocolInterestRatePerSecond = calculateInterestPerSecond(
            offer.amount,
            protocolInterestBps,
            offer.duration
        );
        loanAuction.slashableLenderInterest = 0;
        loanAuction.unpaidProtocolInterest = 0;
    }

    /// @inheritdoc ILending
    function transferNft(
        address nftContractAddress,
        uint256 nftId,
        address to
    ) external whenNotPaused nonReentrant {
        _requireExpectedContract();
        _transferNft(nftContractAddress, nftId, address(this), to);
    }

    function _transferNft(
        address nftContractAddress,
        uint256 nftId,
        address from,
        address to
    ) internal {
        IERC721Upgradeable(nftContractAddress).safeTransferFrom(from, to, nftId);
    }

    /// @inheritdoc ILending
    function approveNft(
        address nftContractAddress,
        uint256 nftId,
        address to
    ) external whenNotPaused nonReentrant {
        _requireSellOnSeaportContract();
        IERC721Upgradeable(nftContractAddress).approve(to, nftId);
    }

    function _payoutCTokenBalances(
        LoanAuction storage loanAuction,
        address cAsset,
        uint256 totalCTokens,
        uint256 totalPayment,
        bool repayFull
    ) internal {
        uint256 cTokensToLender = totalCTokens;

        if (repayFull) {
            uint256 cTokensToProtocol = (totalCTokens * loanAuction.unpaidProtocolInterest) /
                totalPayment;
            cTokensToLender -= cTokensToProtocol;

            ILiquidity(liquidityContractAddress).addToCAssetBalance(
                owner(),
                cAsset,
                cTokensToProtocol
            );
        }

        ILiquidity(liquidityContractAddress).addToCAssetBalance(
            loanAuction.lender,
            cAsset,
            cTokensToLender
        );
    }

    function _handleLoanPayment(address asset, uint256 payment) internal returns (uint256) {
        if (asset == ETH_ADDRESS) {
            return ILiquidity(liquidityContractAddress).mintCEth{ value: payment }();
        } else {
            require(msg.value == 0, "00023");
            return ILiquidity(liquidityContractAddress).mintCErc20(msg.sender, asset, payment);
        }
    }

    function _currentTimestamp32() internal view returns (uint32) {
        return SafeCastUpgradeable.toUint32(block.timestamp);
    }

    // solhint-disable-next-line no-empty-blocks
    function renounceOwnership() public override onlyOwner {}
}
