pragma solidity ^0.8.11;
//SPDX-License-Identifier: MIT

import "./LiquidityProviders.sol";
import "./interfaces/compound/ICEther.sol";
import "./interfaces/ILendingAuction.sol";
import "./interfaces/compound/ICERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/Address.sol";

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

    // ---------- STATE VARIABLES --------------- //

    // Mapping of nftId to nftContractAddress to LoanAuction struct
    mapping(address => mapping(uint256 => LoanAuction)) _loanAuctions;

    mapping(address => mapping(uint256 => mapping(bytes32 => Offer))) _nftOfferBooks;
    mapping(address => mapping(bytes32 => Offer)) _floorOfferBooks;

    // Cancelled / finalized orders, by signature
    mapping(bytes => bool) _cancelledOrFinalized;

    // fee in basis points paid to protocol by borrower for drawing down loan
    uint64 public loanDrawFeeProtocolBps = 50;

    // premium in basis points paid to current lender by new lender for buying out the loan
    uint64 public refinancePremiumLenderBps = 50;

    // premium in basis points paid to protocol by new lender for buying out the loan
    uint64 public refinancePremiumProtocolBps = 50;

    // ---------- FUNCTIONS -------------- //

    /**
     * @notice Construct contract with pre-appended information for EIP712 signatures
     */
    constructor() EIP712("NiftyApes", "0.0.1") {}

    /**
     * @notice Retrieve data about a given loan auction
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of a specified NFT
     */

    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory)
    {
        return _loanAuctions[nftContractAddress][nftId];
    }

    /**
     * @notice Generate a hash of an offer and sign with the EIP712 standard
     * @param offer The details of a loan auction offer
     */
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

    /**
     * @notice Check whether a signature-based offer has been cancelledOrFinalized
     * @param signature A signed offerHash
     */
    function getOfferSignatureStatus(bytes calldata signature) external view returns (bool status) {
        status = _cancelledOrFinalized[signature];
    }

    /**
     * @notice Get the offer signer given an offerHash and signature for the offer.
     * @param eip712EncodedOffer encoded hash of an offer (from LoanAuction.getEIP712EncodedOffer(offer))
     * @param signature The 65 byte (r, s, v) signature of a signedOffer
     */
    function getOfferSigner(
        bytes32 eip712EncodedOffer, // hash of offer
        bytes memory signature //proof the actor signed the offer
    ) public pure returns (address) {
        return ECDSA.recover(eip712EncodedOffer, signature);
    }

    /**
     * @notice Cancel a signature based offer on chain
     * @dev This function is the only way to ensure an offer can't be used on chain
     */
    function withdrawOfferSignature(
        address nftContractAddress,
        uint256 nftId,
        bytes32 eip712EncodedOffer,
        bytes calldata signature
    ) external {
        // require signature is still valid. This also ensures the signature is not utilized in an active loan
        require(!_cancelledOrFinalized[signature], "Already cancelled or finalized.");

        // recover signer
        address signer = getOfferSigner(eip712EncodedOffer, signature);

        // Require that msg.sender is signer of the signature
        require(signer == msg.sender, "Msg.sender is not the signer of the submitted signature");

        // cancel signature
        _cancelledOrFinalized[signature] = true;

        emit SigOfferCancelled(nftContractAddress, nftId, signature);
    }

    // ---------- On-chain Offer Functions ---------- //

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

    /**
     * @notice Retrieve an offer from the on-chain floor or individual NFT offer books by offerHash identifier
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer
     * @param floorTerm Indicates whether this is a floor or individual NFT offer. true = floor offer. false = individual NFT offer
     */
    function getOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external view returns (Offer memory) {
        return getOfferBook(nftContractAddress, nftId, floorTerm)[offerHash];
    }

    /**
     * @param offer The details of the loan auction individual NFT offer
     */
    function createOffer(Offer calldata offer) external {
        address cAsset = getCAsset(offer.asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        require(offer.creator == msg.sender, "creator != sender");

        uint256 offerTokens = assetAmountToCAssetAmount(offer.asset, offer.amount);

        // require msg.sender has sufficient available balance of cErc20
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

    /**
     * @notice Remove an offer in the on-chain floor offer book
     * @param nftContractAddress The address of the NFT collection
     * @param offerHash The hash of all parameters in an offer
     */
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

    // ---------- Execute Loan Functions ---------- //

    /**
     * @notice Allows a borrower to submit an offer from the on-chain NFT offer book and execute a loan using their NFT as collateral
     * @param nftContractAddress The address of the NFT collection
     * @param floorTerm Whether or not this is a floor term
     * @param nftId The id of the specified NFT (ignored for floor term)
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
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

    /**
     * @notice Allows a borrower to submit a signed offer from a lender and execute a loan using their NFT as collateral
     * @param offer The details of the loan auction offer
     * @param signature A signed offerHash
     * @param nftId The id of a specified NFT
     */
    function executeLoanByBorrowerSignature(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId // nftId should match offer.nftId if offer.floorTerm false, nftId should not match if offer.floorTerm true. Need to provide as function parameter to pass nftId with floor terms.
    ) external payable whenNotPaused nonReentrant {
        // require signature has not been cancelled/bid withdrawn
        require(
            !_cancelledOrFinalized[signature],
            "Cannot execute bid or ask. Signature has been cancelled or previously finalized."
        );

        // ideally calculated, stored, and provided as parameter to save computation
        // generate hash of offer parameters
        bytes32 encodedOffer = getEIP712EncodedOffer(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // we know the signer must be the lender because msg.sender must be the nftOwner/borrower
        address lender = getOfferSigner(encodedOffer, signature);

        require(lender == offer.creator, "Offer.creator must be offer signer to executeLoanByBid");

        // // if floorTerm is false
        if (!offer.floorTerm) {
            // require nftId == sigNftId
            require(
                nftId == offer.nftId,
                "Function submitted nftId must match the signed offer nftId"
            );
        }

        // execute state changes for executeLoanByBid
        _executeLoanInternal(offer, lender, msg.sender, nftId);

        // finalize signature
        _cancelledOrFinalized[signature] = true;

        emit SigOfferFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    /**
     * @notice Allows a lender to submit an offer from the borrower in the on-chain individual NFT offer book and execute a loan using the borrower's NFT as collateral
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
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

    /**
     * @notice Allows a lender to submit a signed offer from a borrower and execute a loan using the borrower's NFT as collateral
     * @param offer The details of the loan auction offer
     * @param signature A signed offerHash
     */
    function executeLoanByLenderSignature(Offer calldata offer, bytes calldata signature)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        // require signature has not been cancelled/bid withdrawn
        require(
            !_cancelledOrFinalized[signature],
            "Cannot execute bid or ask. Signature has been cancelled or previously finalized."
        );

        bytes32 encodedOffer = getEIP712EncodedOffer(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // We assume the signer is the borrower and check in the following require statement
        address borrower = getOfferSigner(encodedOffer, signature);

        // execute state changes for executeLoanByAsk
        _executeLoanInternal(offer, msg.sender, borrower, offer.nftId);

        // finalize signature
        _cancelledOrFinalized[signature] = true;

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
            Address.sendValue(payable(borrower), offer.amount);
        } else {
            IERC20(offer.asset).safeTransfer(borrower, offer.amount);
        }

        emit LoanExecuted(lender, borrower, offer.nftContractAddress, offer.nftId, offer);
    }

    // ---------- Refinance Loan Functions ---------- //

    /**
     * @notice Allows a borrower to submit an offer from the on-chain offer book and refinance a loan with near arbitrary terms
     * @dev The offer amount must be greater than the current loan amount plus interest owed to the lender
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
    function refinanceByBorrower(
        address nftContractAddress,
        bool floorTerm,
        uint256 nftId,
        bytes32 offerHash
    ) external payable whenNotPaused nonReentrant {
        Offer memory offer = floorTerm
            ? _floorOfferBooks[nftContractAddress][offerHash]
            : _nftOfferBooks[nftContractAddress][nftId][offerHash];

        if (!floorTerm) {
            require(
                nftId == offer.nftId,
                "Function submitted nftId must match the signed offer nftId"
            );
        }

        // check if nftOwner and require msg.sender is the nftOwner/borrower in the protocol
        require(
            msg.sender == ownerOf(nftContractAddress, nftId),
            "Msg.sender must be the owner of nftId to refinanceByBorrower"
        );

        _refinance(offer, offer.creator, nftId, true);
    }

    /**
     * @notice Allows a borrower to submit a signed offer from a lender and refinance a loan with near arbitrary terms
     * @dev The offer amount must be greater than the current loan amount plus interest owed to the lender
     * @param offer The details of the loan auction offer
     * @param signature A signed offerHash
     * @param nftId The id of a specified NFT
     */
    function refinanceByBorrowerSignature(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId
    ) external payable whenNotPaused nonReentrant {
        // ideally calculated, stored, and provided as parameter to save computation
        bytes32 encodedOffer = getEIP712EncodedOffer(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // We assume the signer is the lender because msg.sender must the the nftOwner
        address prospectiveLender = getOfferSigner(encodedOffer, signature);

        require(offer.creator == prospectiveLender, "Signer must be the offer.creator");

        if (!offer.floorTerm) {
            // require nftId == sigNftId
            require(
                nftId == offer.nftId,
                "Function submitted nftId must match the signed offer nftId"
            );
        }

        // check if nftOwner and require msg.sender is the nftOwner/borrower in the protocol
        require(
            msg.sender == ownerOf(offer.nftContractAddress, nftId),
            "Msg.sender must be the owner of nftId to refinanceByBorrower"
        );

        _refinance(offer, offer.creator, nftId, true);

        // ensure all sig functions finalize signatures

        // finalize signature
        _cancelledOrFinalized[signature] = true;

        emit SigOfferFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    /**
     * @notice Allows a lender to offer better terms than the current loan, refinance, and take over a loan
     * @dev The offer amount, interest rate, and duration must be at parity with the current loan, plus "1". Meaning at least one term must be better than the current loan.
     * @dev new lender balance must be sufficient to pay fullRefinance amount
     * @dev current lender balance must be sufficient to fund new offer amount
     * @param offer The details of the loan auction offer
     */
    function refinanceByLender(Offer calldata offer) external payable whenNotPaused nonReentrant {
        uint256 timeDrawn = _loanAuctions[offer.nftContractAddress][offer.nftId].timeDrawn;
        uint256 loanExecutedTime = _loanAuctions[offer.nftContractAddress][offer.nftId]
            .loanExecutedTime;
        uint256 amount = _loanAuctions[offer.nftContractAddress][offer.nftId].amount;
        uint256 interestRateBps = _loanAuctions[offer.nftContractAddress][offer.nftId]
            .interestRateBps;
        uint256 duration = _loanAuctions[offer.nftContractAddress][offer.nftId].duration;

        // Require that loan has not expired. This prevents another lender from refinancing
        require(
            block.timestamp < loanExecutedTime + timeDrawn,
            "Cannot refinance loan that has expired"
        );

        // require that terms are parity + 1
        require(
            // Require bidAmount is greater than previous bid
            (offer.amount > amount &&
                offer.interestRateBps <= interestRateBps &&
                offer.duration >= duration) ||
                // OR
                // Require interestRate is lower than previous bid
                (offer.amount >= amount &&
                    offer.interestRateBps < interestRateBps &&
                    offer.duration >= duration) ||
                // OR
                // Require duration to be greater than previous bid
                (offer.amount >= amount &&
                    offer.interestRateBps <= interestRateBps &&
                    offer.duration > duration),
            "Bid must have better terms than current loan"
        );

        // if duration is the only term updated
        if (
            offer.amount >= amount &&
            offer.interestRateBps >= interestRateBps &&
            offer.duration > duration
        ) {
            // require offer has at least 24 hour additional duration
            require(
                offer.duration >= (duration + 1 days),
                "Cannot refinanceBestOffer. Offer duration must be at least 24 hours greater than current loan. "
            );
        }

        _refinance(offer, offer.creator, offer.nftId, false);
    }

    // @Alcibades - we must supply the nftId to support floor offers. A floor offer will have only one nftId yet be valid for n nfts.
    /**
     * @notice Handles internal checks, state transitions, and value/asset transfers for loan refinance
     * @param offer The details of a loan auction offer
     * @param prospectiveLender The prospective lender
     */
    function _refinance(
        Offer memory offer,
        address prospectiveLender,
        uint256 nftId,
        bool byBorrower
    ) internal {
        // Get information about present loan from storage
        // Can't accessing members directly in this function without triggering a 'stack too deep' error
        LoanAuction storage loanAuction = _loanAuctions[offer.nftContractAddress][offer.nftId];

        // Require that loan does not have fixedTerms
        require(!loanAuction.fixedTerms, "fixed term loan");

        requireOpenLoan(loanAuction);
        requireOfferNotExpired(offer);
        requireMinDurationForOffer(offer);

        requireMatchingAsset(offer.asset, loanAuction.asset);

        address cAsset = getCAsset(offer.asset);

        // calculate the interest earned by current lender
        (uint256 currentLenderInterest, uint256 currentProtocolInterest) = calculateInterestAccrued(
            offer.nftContractAddress,
            nftId
        );

        if (byBorrower) {
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
            loanAuction.amountDrawn = fullAmount;
            loanAuction.timeOfInterestStart = block.timestamp;
            loanAuction.historicLenderInterest += currentLenderInterest;
            loanAuction.historicProtocolInterest += currentProtocolInterest;
        } else {
            // calculate interest earned
            uint256 interestAndPremiumOwedToCurrentLender = currentLenderInterest +
                loanAuction.historicLenderInterest +
                ((loanAuction.amountDrawn * refinancePremiumLenderBps) / 10000);

            uint256 protocolPremium = (loanAuction.amountDrawn * refinancePremiumProtocolBps) /
                10000;

            // calculate fullRefinanceAmount
            uint256 fullAmount = interestAndPremiumOwedToCurrentLender +
                protocolPremium +
                loanAuction.amountDrawn;

            // update LoanAuction struct
            loanAuction.amount = offer.amount;
            loanAuction.interestRateBps = offer.interestRateBps;
            loanAuction.duration = offer.duration;
            loanAuction.timeOfInterestStart = block.timestamp;
            loanAuction.historicLenderInterest += currentLenderInterest;
            loanAuction.historicProtocolInterest += currentProtocolInterest;

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

                // TODO(dankurka): numbers are not matching
                _accountAssets[currentlender][cAsset].cAssetBalance +=
                    fullCTokenAmount -
                    protocolPremimuimInCtokens;
                _accountAssets[prospectiveLender][cAsset].cAssetBalance -= fullCTokenAmount;
                // TODO(dankurka): This is still sus since it we are also adding to the historic part?!
                _accountAssets[owner()][cAsset].cAssetBalance += protocolPremimuimInCtokens;
            }
        }

        emit Refinance(prospectiveLender, offer.nftContractAddress, offer.nftId, offer);
    }

    // // ---------- Borrower Draw Functions ---------- //

    /**
     * @notice If a loan has been refinanced with a longer duration this function allows a borrower to draw down additional time for their loan.
     * @dev Drawing down time increases the maximum loan pay back amount and so is not automatically imposed on a refinance by lender, hence this function.
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param drawTime The amount of time to draw and add to the loan duration
     */
    function drawLoanTime(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawTime
    ) external whenNotPaused nonReentrant {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];

        // Require that loan is active
        require(loanAuction.loanExecutedTime != 0, "Loan is not active. No funds to withdraw.");

        // Require msg.sender is the nftOwner on the nft contract
        require(msg.sender == loanAuction.nftOwner, "Msg.sender is not the NFT owner");

        // document that a user CAN draw more time after a loan has expired, but they are still open to asset siezure until they draw enough time.
        // // Require that loan has not expired
        // require(
        //     block.timestamp <
        //         loanAuction.loanExecutedTime + loanAuction.timeDrawn,
        //     "Cannot draw more time after a loan has expired"
        // );

        // Require timeDrawn is less than the duration. Ensures there is time available to draw
        require(loanAuction.timeDrawn < loanAuction.duration, "Draw Time amount not available");

        // Require that drawTime + timeDrawn does not exceed duration
        require(
            (drawTime + loanAuction.timeDrawn) <= loanAuction.duration,
            "Total Time drawn must not exceed best bid duration"
        );

        (uint256 lenderInterest, uint256 protocolInterest) = calculateInterestAccrued(
            nftContractAddress,
            nftId
        );

        // reset timeOfinterestStart and update historic interest due to parameters of loan changing
        loanAuction.historicLenderInterest += lenderInterest;
        loanAuction.historicProtocolInterest += protocolInterest;
        loanAuction.timeOfInterestStart = block.timestamp;

        // set timeDrawn
        loanAuction.timeDrawn += drawTime;

        emit TimeDrawn(nftContractAddress, nftId, drawTime, loanAuction.timeDrawn);
    }

    /**
     * @notice If a loan has been refinanced with a higher amount this function allows a borrower to draw down additional value for their loan.
     * @dev Drawing down value increases the maximum loan pay back amount and so is not automatically imposed on a refinance by lender, hence this function.
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param drawAmount The amount of value to draw and add to the loan amountDrawn
     */
    function drawLoanAmount(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawAmount
    ) external whenNotPaused nonReentrant {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];

        address cAsset = assetToCAsset[loanAuction.asset];

        // Require that loan is active
        require(loanAuction.loanExecutedTime != 0, "Loan is not active. No funds to withdraw.");

        // Require msg.sender is the borrower
        require(msg.sender == loanAuction.nftOwner, "Msg.sender is not the NFT owner");

        // Require amountDrawn is less than the bestOfferAmount
        require(loanAuction.amountDrawn < loanAuction.amount, "Draw down amount not available");

        // Require that drawAmount does not exceed amount
        require(
            (drawAmount + loanAuction.amountDrawn) <= loanAuction.amount,
            "Total amount withdrawn must not exceed best bid loan amount"
        );

        // Require that loan has not expired
        require(
            block.timestamp < loanAuction.loanExecutedTime + loanAuction.timeDrawn,
            "Cannot draw more value after a loan has expired"
        );

        (uint256 lenderInterest, uint256 protocolInterest) = calculateInterestAccrued(
            nftContractAddress,
            nftId
        );

        // reset timeOfinterestStart and update historic interest due to parameters of loan changing
        loanAuction.historicLenderInterest += lenderInterest;
        loanAuction.historicProtocolInterest += protocolInterest;
        loanAuction.timeOfInterestStart = block.timestamp;

        // set amountDrawn
        loanAuction.amountDrawn += drawAmount;

        uint256 cTokensBurnt = burnCErc20(loanAuction.asset, drawAmount);

        require(
            // calculate lenders available ICERC20 balance and require it to be greater than or equal to redeemTokens
            getCAssetBalance(loanAuction.lender, cAsset) >= cTokensBurnt,
            "Lender does not have a sufficient balance to serve this loan"
        );

        _accountAssets[loanAuction.lender][cAsset].cAssetBalance -= cTokensBurnt;

        if (loanAuction.asset == ETH_ADDRESS) {
            Address.sendValue(payable(loanAuction.nftOwner), drawAmount);
        } else {
            IERC20 underlying = IERC20(loanAuction.asset);
            // transfer underlying from this contract to borrower
            require(
                underlying.transfer(loanAuction.nftOwner, drawAmount),
                "underlying.transfer() failed"
            );
        }

        emit AmountDrawn(nftContractAddress, nftId, drawAmount, loanAuction.amountDrawn);
    }

    // ---------- Repayment and Asset Seizure Functions ---------- //

    /**
     * @notice Enables a borrower to repay the remaining value of their loan plus interest and protocol fee, and regain full ownership of their NFT
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     */
    function repayLoan(address nftContractAddress, uint256 nftId) external payable override {
        _repayLoanAmount(nftContractAddress, nftId, true, 0);
    }

    /**
     * @notice Allows borrowers to make a partial payment toward the principle of their loan
     * @dev This function does not charge any interest or fees. It does change the calculation for future interest and fees accrual, so we track historicLenderInterest and historicProtocolInterest
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param amount The amount of value to pay down on the principle of the loan
     */
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
            require(paymentAmount == msg.value, "wrong data");
        }

        requireOpenLoan(loanAuction);

        // TODO(dankurka): Maybe we should allow others to repay your loan
        require(msg.sender == loanAuction.nftOwner, "Msg.sender is not the NFT owner");

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
                Address.sendValue(payable(msg.sender), msg.value - payment);
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
            // reset loanAuction
            delete _loanAuctions[nftContractAddress][nftId];

            // transferFrom NFT from contract to nftOwner
            IERC721(nftContractAddress).transferFrom(address(this), msg.sender, nftId);

            emit LoanRepaid(nftContractAddress, nftId);
        } else {
            emit PartialRepayment(nftContractAddress, nftId, loanAuction.asset, paymentAmount);
        }
    }

    /**
     * @notice Allows anyone to seize an asset of a past due loan on behalf on the lender
     * @dev This functions can be called by anyone the second the duration + loanExecutedTime is past and the loan is not paid back in full
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     */
    function seizeAsset(address nftContractAddress, uint256 nftId)
        external
        whenNotPaused
        nonReentrant
    {
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];
        address cAsset = getCAsset(loanAuction.asset);
        requireOpenLoan(loanAuction);

        requireLoanExpired(loanAuction);

        address currentlender = loanAuction.lender;

        delete _loanAuctions[nftContractAddress][nftId];

        IERC721(nftContractAddress).transferFrom(address(this), currentlender, nftId);

        emit AssetSeized(nftContractAddress, nftId);
    }

    // ---------- Helper Functions ---------- //

    function ownerOf(address nftContractAddress, uint256 nftId) public view returns (address) {
        return _loanAuctions[nftContractAddress][nftId].nftOwner;
    }

    // returns the interest value earned by lender or protocol during timeOfInterest segment
    function calculateInterestAccrued(address nftContractAddress, uint256 nftId)
        public
        view
        returns (uint256 lenderInterest, uint256 protocolInterest)
    {
        uint256 timeDrawn = _loanAuctions[nftContractAddress][nftId].timeDrawn;
        uint256 amountDrawn = _loanAuctions[nftContractAddress][nftId].amountDrawn;
        uint256 loanExecutedTime = _loanAuctions[nftContractAddress][nftId].loanExecutedTime;
        uint256 timeOfInterestStart = _loanAuctions[nftContractAddress][nftId].timeOfInterestStart;
        uint64 interestRateBps = _loanAuctions[nftContractAddress][nftId].interestRateBps;

        if (
            block.timestamp <= timeOfInterestStart ||
            timeDrawn == 0 ||
            amountDrawn == 0 ||
            loanExecutedTime == 0
        ) {
            protocolInterest = 0;
            lenderInterest = 0;
        } else {
            uint256 timeOutstanding = block.timestamp - timeOfInterestStart;

            uint256 maxDrawn = amountDrawn * timeDrawn;

            uint256 fractionOfDrawn = maxDrawn / timeOutstanding;

            lenderInterest = (interestRateBps * fractionOfDrawn) / 10000;

            protocolInterest = (loanDrawFeeProtocolBps * fractionOfDrawn) / 10000;
        }
    }

    // provide an upper bound at 1000 bps or similar

    function updateLoanDrawProtocolFee(uint64 newLoanDrawProtocolFeeBps) external onlyOwner {
        loanDrawFeeProtocolBps = newLoanDrawProtocolFeeBps;
    }

    function updateRefinancePremiumLenderFee(uint64 newPremiumLenderBps) external onlyOwner {
        refinancePremiumLenderBps = newPremiumLenderBps;
    }

    function updateRefinancePremiumProtocolFee(uint64 newPremiumProtocolBps) external onlyOwner {
        refinancePremiumProtocolBps = newPremiumProtocolBps;
    }

    function requireOfferPresent(Offer memory offer) internal pure {
        require(offer.asset != address(0), "no offer");
    }

    function requireNoOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.loanExecutedTime == 0, "Loan already open");
    }

    function requireOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.loanExecutedTime != 0, "loan not active");
    }

    function requireLoanExpired(LoanAuction storage loanAuction) internal view {
        require(
            block.timestamp >= loanAuction.loanExecutedTime + loanAuction.timeDrawn,
            "loan not expired"
        );
    }

    function requireOfferNotExpired(Offer memory offer) internal view {
        require(offer.expiration > block.timestamp, "offer expired");
    }

    function requireMinDurationForOffer(Offer memory offer) internal view {
        require(offer.duration >= 1 days, "offer duration");
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
        loanAuction.timeOfInterestStart = block.timestamp;
        loanAuction.loanExecutedTime = block.timestamp;
        loanAuction.timeDrawn = offer.duration;
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;
    }
}
