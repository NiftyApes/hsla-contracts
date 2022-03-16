pragma solidity ^0.8.11;
//SPDX-License-Identifier: Unlicensed

import "./LiquidityProviders.sol";
import "./interfaces/compound/ICEther.sol";
import "./interfaces/ILendingAuction.sol";
import "./interfaces/compound/ICERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title NiftyApes LendingAuction Contract
 * @notice Harberger Style Lending Auctions for any collection or asset in existence at any time.
 * @author NiftyApes
 */

//  TODO Comment each function and each line of funtionality for readability by auditors - essential
// TODO(Use the non mutating libcompound type implementation for major gas savings) - nice to have
// A major issue is the libcompound has not been audited at this point in time
// TODO(Can the offer book mapping be factored out to a library?) - nice to have
// I dont think so due to storage value needed in the library
// TODO(need to implement Proxy and Intitializable contracts to enable upgarability and big fixes?)

// TODO refactor to ensure that capital can't be moved or is present for amountDrawn

contract LendingAuction is ILendingAuction, LiquidityProviders, EIP712 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @notice The maximum value that any fee on the protocol can be set to.
    ///         Fees on the protocol are denomimated in parts of 10_000.
    uint16 constant MAX_FEE = 1000;

    uint16 constant MAX_BPS = 10000;

    /// @dev A mapping for a NFT to a loan auction.
    ///      The mapping has to be broken into two parts since an NFT is denomiated by its address (first part)
    ///      and its nftId (second part) in our code base.
    mapping(address => mapping(uint256 => LoanAuction)) _loanAuctions;

    /// @dev A mapping for a NFT to an Offer
    ///      The mapping has to be broken into three parts since an NFT is denomiated by its address (first part)
    ///      and its nftId (second part), offers are reffered to by their hash (see #getEIP712EncodedOffer for details) (third part).
    mapping(address => mapping(uint256 => mapping(bytes32 => Offer))) _nftOfferBooks;

    /// @dev A mapping for a NFT to a floor offer
    ///      Floor offers are different from offers on a specific NFT since they are valid on any NFT fro the same address.
    ///      Thus this mapping skips the nftId, see _nftOfferBooks above.
    mapping(address => mapping(bytes32 => Offer)) _floorOfferBooks;

    /// @dev A mapping to mark a signature as used.
    ///      The mapping allows users to withdraw offers that they made by signature.
    mapping(bytes => bool) _cancelledOrFinalized;

    /// @inheritdoc ILendingAuction
    uint16 public loanDrawFeeProtocolBps = 50;

    /// @inheritdoc ILendingAuction
    uint16 public refinancePremiumLenderBps = 50;

    /// @inheritdoc ILendingAuction
    uint16 public refinancePremiumProtocolBps = 50;

    /**
     * @notice Construct contract with pre-appended information for EIP712 signatures
     */
    constructor() EIP712("NiftyApes", "0.0.1") {}

    /// @inheritdoc ILendingAuction
    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory)
    {
        return _loanAuctions[nftContractAddress][nftId];
    }

    /// @inheritdoc ILendingAuction
    function getEIP712EncodedOffer(Offer memory offer) public view returns (bytes32 signedOffer) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        offer.creator,
                        offer.nftContractAddress,
                        offer.nftId,
                        offer.asset,
                        offer.amount,
                        offer.interestRateBps,
                        offer.duration,
                        offer.expiration,
                        offer.fixedTerms,
                        offer.floorTerm
                    )
                )
            );
    }

    // ---------- Signature Offer Functions ---------- //

    /// @inheritdoc ILendingAuction
    function getOfferSignatureStatus(bytes calldata signature) external view returns (bool) {
        return _cancelledOrFinalized[signature];
    }

    /**
     * @notice Get the offer signer given an offerHash and signature for the offer.
     * @param eip712EncodedOffer encoded hash of an offer (from LoanAuction.getEIP712EncodedOffer(offer))
     * @param signature The 65 byte (r, s, v) signature of a signedOffer
     */
    function getOfferSigner(
        bytes32 eip712EncodedOffer, // hash of offer
        bytes memory signature //proof the actor signed the offer
    ) internal pure returns (address) {
        return ECDSA.recover(eip712EncodedOffer, signature);
    }

    /// @inheritdoc ILendingAuction
    function withdrawOfferSignature(
        // TODO(dankurka): These params have not been validated (but we output them in the event)
        address nftContractAddress,
        uint256 nftId,
        bytes32 eip712EncodedOffer,
        bytes calldata signature
    ) external {
        requireAvailableSignature(signature);

        address signer = getOfferSigner(eip712EncodedOffer, signature);

        // Require that msg.sender is signer of the signature
        require(signer == msg.sender, "Msg.sender is not the signer of the submitted signature");

        markSignatureUsed(signature);

        emit SigOfferCancelled(nftContractAddress, nftId, signature);
    }

    function getOfferBook(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm
    ) internal view returns (mapping(bytes32 => Offer) storage) {
        return
            floorTerm
                ? _floorOfferBooks[nftContractAddress]
                : _nftOfferBooks[nftContractAddress][nftId];
    }

    /// @inheritdoc ILendingAuction
    function getOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external view returns (Offer memory) {
        return getOfferBook(nftContractAddress, nftId, floorTerm)[offerHash];
    }

    /// @inheritdoc ILendingAuction
    function createOffer(Offer calldata offer) external {
        address cAsset = getCAsset(offer.asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        require(offer.creator == msg.sender, "creator != sender");

        uint256 offerTokens = assetAmountToCAssetAmount(offer.asset, offer.amount);

        require(getCAssetBalance(msg.sender, cAsset) >= offerTokens, "Insufficient lender balance");

        mapping(bytes32 => Offer) storage offerBook = getOfferBook(
            offer.nftContractAddress,
            offer.nftId,
            offer.floorTerm
        );

        bytes32 offerHash = getEIP712EncodedOffer(offer);

        offerBook[offerHash] = offer;

        emit NewOffer(
            offer.creator,
            offer.asset,
            offer.nftContractAddress,
            offer.nftId,
            offer,
            offerHash
        );
    }

    /// @inheritdoc ILendingAuction
    function removeOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external {
        // Get pointer to offer book
        mapping(bytes32 => Offer) storage offerBook = getOfferBook(
            nftContractAddress,
            nftId,
            floorTerm
        );

        // Create a copy here so that we can log out the event below
        Offer memory offer = offerBook[offerHash];

        require(msg.sender == offer.creator, "wrong offer creator");

        delete offerBook[offerHash];

        emit OfferRemoved(offer.creator, offer.asset, offer.nftContractAddress, offer, offerHash);
    }

    /// @inheritdoc ILendingAuction
    function executeLoanByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external payable whenNotPaused nonReentrant {
        mapping(bytes32 => Offer) storage offerBook = getOfferBook(
            nftContractAddress,
            nftId,
            floorTerm
        );
        Offer memory offer = offerBook[offerHash];

        _executeLoanInternal(offer, offer.creator, msg.sender, nftId);
    }

    /// @inheritdoc ILendingAuction
    function executeLoanByBorrowerSignature(
        Offer calldata offer,
        bytes calldata signature,
        // TODO(dankurka): Discuss with kevin
        uint256 nftId // nftId should match offer.nftId if offer.floorTerm false, nftId should not match if offer.floorTerm true. Need to provide as function parameter to pass nftId with floor terms.
    ) external payable whenNotPaused nonReentrant {
        requireAvailableSignature(signature);

        address lender = getOfferSigner(getEIP712EncodedOffer(offer), signature);
        requireOfferCreator(offer, lender);

        if (!offer.floorTerm) {
            requireMatchingNftId(offer, nftId);
        }

        markSignatureUsed(signature);

        // execute state changes for executeLoanByBid
        _executeLoanInternal(offer, lender, msg.sender, nftId);

        emit SigOfferFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    /// @inheritdoc ILendingAuction
    function executeLoanByLender(
        address nftContractAddress,
        bool floorTerm,
        uint256 nftId,
        bytes32 offerHash
    ) public payable whenNotPaused nonReentrant {
        Offer memory offer = floorTerm
            ? _floorOfferBooks[nftContractAddress][offerHash]
            : _nftOfferBooks[nftContractAddress][nftId][offerHash];

        // execute state changes for executeLoanByAsk
        _executeLoanInternal(offer, msg.sender, offer.creator, nftId);
    }

    /// @inheritdoc ILendingAuction
    function executeLoanByLenderSignature(Offer calldata offer, bytes calldata signature)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        requireAvailableSignature(signature);

        address borrower = getOfferSigner(getEIP712EncodedOffer(offer), signature);
        requireOfferCreator(offer, borrower);

        markSignatureUsed(signature);

        _executeLoanInternal(offer, msg.sender, borrower, offer.nftId);

        emit SigOfferFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    /**
     * @notice Handles checks, state transitions, and value/asset transfers for executeLoanbyLender
     * @param offer The details of a loan auction offer
     * @param lender The prospective lender
     * @param borrower The prospective borrower and owner of the NFT
     */
    function _executeLoanInternal(
        Offer memory offer,
        address lender,
        address borrower,
        uint256 nftId
    ) internal {
        requireOfferPresent(offer);

        address cAsset = getCAsset(offer.asset);

        LoanAuction storage loanAuction = _loanAuctions[offer.nftContractAddress][offer.nftId];

        requireNoOpenLoan(loanAuction);
        requireOfferNotExpired(offer);
        requireMinDurationForOffer(offer);
        requireNftOwner(offer.nftContractAddress, nftId, borrower);

        createLoan(loanAuction, offer, lender, borrower);

        IERC721(offer.nftContractAddress).transferFrom(borrower, address(this), offer.nftId);

        uint256 cTokensBurned = burnCErc20(offer.asset, offer.amount);
        withdrawCBalance(lender, cAsset, cTokensBurned);

        if (offer.asset == ETH_ADDRESS) {
            payable(borrower).sendValue(offer.amount);
        } else {
            IERC20(offer.asset).safeTransfer(borrower, offer.amount);
        }

        emit LoanExecuted(lender, borrower, offer.nftContractAddress, offer.nftId, offer);
    }

    /// @inheritdoc ILendingAuction
    function refinanceByBorrower(
        address nftContractAddress,
        bool floorTerm,
        uint256 nftId,
        bytes32 offerHash
    ) external payable whenNotPaused nonReentrant {
        Offer memory offer = floorTerm
            ? _floorOfferBooks[nftContractAddress][offerHash]
            : _nftOfferBooks[nftContractAddress][nftId][offerHash];

        if (!offer.floorTerm) {
            requireMatchingNftId(offer, nftId);
        }

        requireNftOwner(_loanAuctions[nftContractAddress][nftId], msg.sender);
        _refinanceByBorrower(offer, offer.creator, nftId);
    }

    /// @inheritdoc ILendingAuction
    function refinanceByBorrowerSignature(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId
    ) external payable whenNotPaused nonReentrant {
        address prospectiveLender = getOfferSigner(getEIP712EncodedOffer(offer), signature);

        requireOfferCreator(offer, prospectiveLender);

        if (!offer.floorTerm) {
            requireMatchingNftId(offer, nftId);
        }

        requireNftOwner(_loanAuctions[offer.nftContractAddress][offer.nftId], msg.sender);

        markSignatureUsed(signature);

        _refinanceByBorrower(offer, offer.creator, nftId);

        emit SigOfferFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    /// @inheritdoc ILendingAuction
    function refinanceByLender(Offer calldata offer) external payable whenNotPaused nonReentrant {
        LoanAuction storage loanAuction = _loanAuctions[offer.nftContractAddress][offer.nftId];

        requireOpenLoan(loanAuction);

        requireLoanNotExpired(loanAuction);

        requireOfferParity(loanAuction, offer);

        // TODO(dankurka): Look at duration
        // if duration is the only term updated
        if (
            offer.amount >= loanAuction.amount &&
            offer.interestRateBps >= loanAuction.interestRateBps &&
            offer.duration > loanAuction.duration
        ) {
            // require offer has at least 24 hour additional duration
            require(
                offer.duration >= (loanAuction.duration + 1 days),
                "Cannot refinanceBestOffer. Offer duration must be at least 24 hours greater than current loan. "
            );
        }

        _refinanceByLender(offer, offer.creator, offer.nftId);
    }

    function _refinanceByBorrower(
        Offer memory offer,
        address prospectiveLender,
        uint256 nftId
    ) internal {
        (LoanAuction storage loanAuction, address cAsset) = _refinanceCheckState(offer);

        (uint256 currentLenderInterest, uint256 currentProtocolInterest) = calculateInterestAccrued(
            offer.nftContractAddress,
            nftId
        );

        uint256 interestedOwed = currentLenderInterest + loanAuction.historicLenderInterest;
        uint256 fullAmount = loanAuction.amountDrawn + interestedOwed;

        require(
            offer.amount >= fullAmount,
            "The loan offer must exceed the present outstanding balance."
        );

        // Get the full amount of the loan outstanding balance in cTokens
        uint256 fullCTokenAmount = assetAmountToCAssetAmount(offer.asset, fullAmount);

        withdrawCBalance(prospectiveLender, cAsset, fullCTokenAmount);
        _accountAssets[loanAuction.lender][cAsset].cAssetBalance += fullCTokenAmount;

        // update Loan state
        loanAuction.lender = prospectiveLender;
        loanAuction.amount = offer.amount;
        loanAuction.interestRateBps = offer.interestRateBps;
        loanAuction.duration = offer.duration;
        loanAuction.amountDrawn = SafeCast.toUint128(fullAmount);
        loanAuction.timeOfInterestStart = SafeCast.toUint32(block.timestamp);
        loanAuction.historicLenderInterest += SafeCast.toUint128(currentLenderInterest);
        loanAuction.historicProtocolInterest += SafeCast.toUint128(currentProtocolInterest);

        emit Refinance(prospectiveLender, offer.nftContractAddress, offer.nftId, offer);
    }

    function _refinanceByLender(
        Offer memory offer,
        address prospectiveLender,
        uint256 nftId
    ) internal {
        (LoanAuction storage loanAuction, address cAsset) = _refinanceCheckState(offer);

        // calculate the interest earned by current lender
        (uint256 currentLenderInterest, uint256 currentProtocolInterest) = calculateInterestAccrued(
            offer.nftContractAddress,
            nftId
        );

        // calculate interest earned
        uint256 interestAndPremiumOwedToCurrentLender = currentLenderInterest +
            loanAuction.historicLenderInterest +
            ((loanAuction.amountDrawn * refinancePremiumLenderBps) / MAX_BPS);

        uint256 protocolPremium = (loanAuction.amountDrawn * refinancePremiumProtocolBps) / MAX_BPS;

        // calculate fullRefinanceAmount
        uint256 fullAmount = interestAndPremiumOwedToCurrentLender +
            protocolPremium +
            loanAuction.amountDrawn;

        // update LoanAuction struct
        loanAuction.amount = offer.amount;
        loanAuction.interestRateBps = offer.interestRateBps;
        loanAuction.duration = offer.duration;
        loanAuction.timeOfInterestStart = SafeCast.toUint32(block.timestamp);
        loanAuction.historicLenderInterest += SafeCast.toUint128(currentLenderInterest);
        loanAuction.historicProtocolInterest += SafeCast.toUint128(currentProtocolInterest);

        if (loanAuction.lender == prospectiveLender) {
            // If current lender is refinancing the loan they do not need to pay any fees or buy themselves out.
            // require prospective lender has sufficient available balance to refinance loan

            uint256 cTokenAmountDrawn = assetAmountToCAssetAmount(
                offer.asset,
                loanAuction.amountDrawn
            );

            uint256 cTokenOfferAmount = assetAmountToCAssetAmount(offer.asset, offer.amount);

            uint256 additionalTokens = cTokenOfferAmount - cTokenAmountDrawn;

            require(
                getCAssetBalance(prospectiveLender, cAsset) >= additionalTokens,
                "lender balance"
            );
        } else {
            // If refinancing is done by another lender they must buy out the loan and pay fees
            uint256 fullCTokenAmount = assetAmountToCAssetAmount(offer.asset, fullAmount);

            // require prospective lender has sufficient available balance to refinance loan
            require(
                getCAssetBalance(prospectiveLender, cAsset) >= fullCTokenAmount,
                "lender balance"
            );

            uint256 protocolPremimuimInCtokens = assetAmountToCAssetAmount(
                offer.asset,
                protocolPremium
            );

            address currentlender = loanAuction.lender;

            // update LoanAuction lender
            loanAuction.lender = prospectiveLender;

            _accountAssets[currentlender][cAsset].cAssetBalance +=
                fullCTokenAmount -
                protocolPremimuimInCtokens;
            _accountAssets[prospectiveLender][cAsset].cAssetBalance -= fullCTokenAmount;
            _accountAssets[owner()][cAsset].cAssetBalance += protocolPremimuimInCtokens;
        }

        emit Refinance(prospectiveLender, offer.nftContractAddress, offer.nftId, offer);
    }

    function _refinanceCheckState(Offer memory offer)
        internal
        returns (LoanAuction storage loanAuction, address)
    {
        LoanAuction storage loanAuction = _loanAuctions[offer.nftContractAddress][offer.nftId];

        requireNoFixedTerm(loanAuction);
        requireOpenLoan(loanAuction);
        requireOfferNotExpired(offer);
        requireMinDurationForOffer(loanAuction, offer);

        requireMatchingAsset(offer.asset, loanAuction.asset);

        return (loanAuction, getCAsset(offer.asset));
    }

    /// @inheritdoc ILendingAuction
    function drawLoanTime(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawTime
    ) external whenNotPaused nonReentrant {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];

        requireOpenLoan(loanAuction);
        requireNftOwner(loanAuction, msg.sender);

        // document that a user CAN draw more time after a loan has expired, but they are still open to asset siezure until they draw enough time.
        // // Require that loan has not expired
        // require(
        //     block.timestamp <
        //         loanAuction.loanExecutedTime + loanAuction.timeDrawn,
        //     "Cannot draw more time after a loan has expired"
        // );

        // TODO(dankurka): Discuss with Kevin
        // Require timeDrawn is less than the duration. Ensures there is time available to draw
        require(loanAuction.timeDrawn < loanAuction.duration, "Draw Time amount not available");

        requireTimeAvailable(loanAuction, drawTime);

        (uint256 lenderInterest, uint256 protocolInterest) = calculateInterestAccrued(
            nftContractAddress,
            nftId
        );

        // reset timeOfinterestStart and update historic interest due to parameters of loan changing
        loanAuction.historicLenderInterest += SafeCast.toUint128(lenderInterest);
        loanAuction.historicProtocolInterest += SafeCast.toUint128(protocolInterest);
        loanAuction.timeOfInterestStart = SafeCast.toUint32(block.timestamp);

        loanAuction.timeDrawn += SafeCast.toUint32(drawTime);

        emit TimeDrawn(nftContractAddress, nftId, drawTime, loanAuction.timeDrawn);
    }

    /// @inheritdoc ILendingAuction
    function drawLoanAmount(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawAmount
    ) external whenNotPaused nonReentrant {
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];

        address cAsset = getCAsset(loanAuction.asset);

        requireOpenLoan(loanAuction);

        requireNftOwner(loanAuction, msg.sender);

        // Require amountDrawn is less than the bestOfferAmount
        // TODO(dankurka): Talk with kevin but this seems redundant
        // require(loanAuction.amountDrawn < loanAuction.amount, "Draw down amount not available");

        requireFundsAvailable(loanAuction, drawAmount);
        requireLoanNotExpired(loanAuction);

        (uint256 lenderInterest, uint256 protocolInterest) = calculateInterestAccrued(
            nftContractAddress,
            nftId
        );

        // reset timeOfinterestStart and update historic interest due to parameters of loan changing
        loanAuction.historicLenderInterest += SafeCast.toUint128(lenderInterest);
        loanAuction.historicProtocolInterest += SafeCast.toUint128(protocolInterest);
        loanAuction.timeOfInterestStart = SafeCast.toUint32(block.timestamp);

        // set amountDrawn
        loanAuction.amountDrawn += SafeCast.toUint128(drawAmount);

        uint256 cTokensBurnt = burnCErc20(loanAuction.asset, drawAmount);
        withdrawCBalance(loanAuction.lender, cAsset, cTokensBurnt);

        if (loanAuction.asset == ETH_ADDRESS) {
            payable(loanAuction.nftOwner).sendValue(drawAmount);
        } else {
            IERC20 underlying = IERC20(loanAuction.asset);
            underlying.safeTransfer(loanAuction.nftOwner, drawAmount);
        }

        emit AmountDrawn(nftContractAddress, nftId, drawAmount, loanAuction.amountDrawn);
    }

    /// @inheritdoc ILendingAuction
    function repayLoan(address nftContractAddress, uint256 nftId) external payable override {
        _repayLoanAmount(nftContractAddress, nftId, true, 0);
    }

    /// @inheritdoc ILendingAuction
    function partialRepayLoan(
        address nftContractAddress,
        uint256 nftId,
        uint256 amount
    ) external payable whenNotPaused nonReentrant {
        _repayLoanAmount(nftContractAddress, nftId, false, amount);
    }

    /**
     * @notice Enables a borrower to repay the remaining value of their loan plus interest and protocol fee, and regain full ownership of their NFT
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     */
    function _repayLoanAmount(
        address nftContractAddress,
        uint256 nftId,
        bool repayFull,
        uint256 paymentAmount
    ) internal {
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];
        address cAsset = getCAsset(loanAuction.asset);

        if (!repayFull && loanAuction.asset == ETH_ADDRESS) {
            requireMsgValue(paymentAmount);
        }

        requireOpenLoan(loanAuction);

        // TODO(dankurka): Discuss Maybe we should allow others to repay your loan
        // require(msg.sender == loanAuction.nftOwner, "Msg.sender is not the NFT owner");

        // calculate the amount of interest accrued by the lender
        (uint256 lenderInterest, uint256 protocolInterest) = calculateInterestAccrued(
            nftContractAddress,
            nftId
        );

        uint256 interestOwedToLender = lenderInterest + loanAuction.historicLenderInterest;
        uint256 interestOwedToProtocol = protocolInterest + loanAuction.historicProtocolInterest;

        uint256 payment = repayFull
            ? interestOwedToLender + interestOwedToProtocol + loanAuction.amountDrawn
            : paymentAmount;

        uint256 cTokensMinted;

        // if asset is not 0x0 process as Erc20
        if (loanAuction.asset != ETH_ADDRESS) {
            cTokensMinted = mintCErc20(msg.sender, address(this), loanAuction.asset, payment);
        } else {
            if (repayFull) {
                require(
                    msg.value >= payment,
                    "Must repay full amount of loan drawn plus interest and fee. Account for additional time for interest."
                );
            }

            cTokensMinted = mintCEth(payment);

            if (payment < msg.value) {
                payable(msg.sender).sendValue(msg.value - payment);
            }
        }

        {
            uint256 cTokensToLender = (cTokensMinted *
                (loanAuction.amountDrawn + interestOwedToLender)) / payment;
            uint256 cTokensToProtocol = (cTokensMinted * interestOwedToProtocol) / payment;

            _accountAssets[loanAuction.lender][cAsset].cAssetBalance += cTokensToLender;
            _accountAssets[owner()][cAsset].cAssetBalance += cTokensToProtocol;
        }

        if (repayFull) {
            delete _loanAuctions[nftContractAddress][nftId];

            IERC721(nftContractAddress).transferFrom(address(this), msg.sender, nftId);

            emit LoanRepaid(nftContractAddress, nftId);
        } else {
            emit PartialRepayment(nftContractAddress, nftId, loanAuction.asset, paymentAmount);
        }
    }

    /// @inheritdoc ILendingAuction
    function seizeAsset(address nftContractAddress, uint256 nftId)
        external
        whenNotPaused
        nonReentrant
    {
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];
        address cAsset = getCAsset(loanAuction.asset);
        requireOpenLoan(loanAuction);

        // TODO(dankurka): Does not take into account that there might be more time available due to a refianance
        requireLoanExpired(loanAuction);

        address currentLender = loanAuction.lender;
        address currentBorrower = loanAuction.nftOwner;

        delete _loanAuctions[nftContractAddress][nftId];

        IERC721(nftContractAddress).transferFrom(address(this), currentLender, nftId);

        emit AssetSeized(currentLender, currentBorrower, nftContractAddress, nftId);
    }

    /// @inheritdoc ILendingAuction
    function ownerOf(address nftContractAddress, uint256 nftId) public view returns (address) {
        return _loanAuctions[nftContractAddress][nftId].nftOwner;
    }

    // returns the interest value earned by lender or protocol during timeOfInterest segment
    function calculateInterestAccrued(address nftContractAddress, uint256 nftId)
        public
        view
        returns (uint256 lenderInterest, uint256 protocolInterest)
    {
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];

        uint256 timeOfInterestStart = loanAuction.timeOfInterestStart;

        if (block.timestamp <= timeOfInterestStart) {
            protocolInterest = 0;
            lenderInterest = 0;
        } else {
            uint256 timeOutstanding = block.timestamp - timeOfInterestStart;

            uint256 maxDrawn = loanAuction.amountDrawn * loanAuction.timeDrawn;

            uint256 fractionOfDrawn = maxDrawn / timeOutstanding;

            lenderInterest = (loanAuction.interestRateBps * fractionOfDrawn) / MAX_BPS;

            protocolInterest = (loanDrawFeeProtocolBps * fractionOfDrawn) / MAX_BPS;
        }
    }

    /// @inheritdoc ILendingAuction
    function updateLoanDrawProtocolFee(uint16 newLoanDrawProtocolFeeBps) external onlyOwner {
        require(newLoanDrawProtocolFeeBps <= MAX_FEE, "max fee");
        loanDrawFeeProtocolBps = newLoanDrawProtocolFeeBps;
    }

    /// @inheritdoc ILendingAuction
    function updateRefinancePremiumLenderFee(uint16 newPremiumLenderBps) external onlyOwner {
        require(newPremiumLenderBps <= MAX_FEE, "max fee");
        refinancePremiumLenderBps = newPremiumLenderBps;
    }

    /// @inheritdoc ILendingAuction
    function updateRefinancePremiumProtocolFee(uint16 newPremiumProtocolBps) external onlyOwner {
        require(newPremiumProtocolBps <= MAX_FEE, "max fee");
        refinancePremiumProtocolBps = newPremiumProtocolBps;
    }

    function markSignatureUsed(bytes memory signature) internal {
        _cancelledOrFinalized[signature] = true;
    }

    function requireOfferPresent(Offer memory offer) internal pure {
        require(offer.asset != address(0), "no offer");
    }

    function requireNoOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.timeOfInterestStart == 0, "Loan already open");
    }

    function requireOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.timeOfInterestStart != 0, "loan not active");
    }

    function requireLoanExpired(LoanAuction storage loanAuction) internal view {
        require(
            block.timestamp >= loanAuction.timeOfInterestStart + loanAuction.timeDrawn,
            "loan not expired"
        );
    }

    function requireLoanNotExpired(LoanAuction storage loanAuction) internal view {
        require(
            block.timestamp < loanAuction.timeOfInterestStart + loanAuction.timeDrawn,
            "loan expired"
        );
    }

    function requireOfferNotExpired(Offer memory offer) internal view {
        require(offer.expiration > block.timestamp, "offer expired");
    }

    function requireMinDurationForOffer(Offer memory offer) internal view {
        require(offer.duration >= 1 days, "offer duration");
    }

    function requireMinDurationForOffer(LoanAuction storage loanAuction, Offer memory offer)
        internal
        view
    {
        // TODO(dankurka): Discuss with Kevin
        require(offer.duration >= loanAuction.duration + 1 days, "offer duration");
    }

    function requireNoFixedTerm(LoanAuction storage loanAuction) internal view {
        require(!loanAuction.fixedTerms, "fixed term loan");
    }

    function requireNftOwner(
        address nftContractAddress,
        uint256 nftId,
        address owner
    ) internal view {
        require(IERC721(nftContractAddress).ownerOf(nftId) == owner, "nft owner");
    }

    function requireMatchingAsset(address asset1, address asset2) internal pure {
        require(asset1 == asset2, "asset mismatch");
    }

    function requireAvailableSignature(bytes memory signature) internal {
        require(!_cancelledOrFinalized[signature], "signature not available");
    }

    function requireFundsAvailable(LoanAuction storage loanAuction, uint256 drawAmount) internal {
        require((drawAmount + loanAuction.amountDrawn) <= loanAuction.amount, "funds overdrawn");
    }

    function requireTimeAvailable(LoanAuction storage loanAuction, uint256 drawTime) internal {
        require((drawTime + loanAuction.timeDrawn) <= loanAuction.duration, "time overdrawn");
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
        require(
            // Require bidAmount is greater than previous bid
            (offer.amount > loanAuction.amount &&
                offer.interestRateBps <= loanAuction.interestRateBps &&
                offer.duration >= loanAuction.duration) ||
                // OR
                // Require interestRate is lower than previous bid
                (offer.amount >= loanAuction.amount &&
                    offer.interestRateBps < loanAuction.interestRateBps &&
                    offer.duration >= loanAuction.duration) ||
                // OR
                // Require duration to be greater than previous bid
                (offer.amount >= loanAuction.amount &&
                    offer.interestRateBps <= loanAuction.interestRateBps &&
                    offer.duration > loanAuction.duration),
            "Bid must have better terms than current loan"
        );
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
        loanAuction.interestRateBps = offer.interestRateBps;
        loanAuction.duration = offer.duration;
        loanAuction.timeOfInterestStart = SafeCast.toUint32(block.timestamp);
        loanAuction.timeDrawn = offer.duration;
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;
    }
}
