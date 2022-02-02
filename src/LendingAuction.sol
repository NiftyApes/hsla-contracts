pragma solidity ^0.8.11;
//SPDX-License-Identifier: MIT

import "./LiquidityProviders.sol";
import "./interfaces/compound/ICEther.sol";
import "./interfaces/ILendingAuction.sol";
import "./interfaces/compound/ICERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

/**
 * @title NiftyApes LendingAuction Contract
 * @notice Harberger Style Lending Auctions for any collection or asset in existence at any time.
 * @author NiftyApes
 */

contract LendingAuction is ILendingAuction, LiquidityProviders, EIP712 {
    using ECDSA for bytes32;

    // ---------- STATE VARIABLES --------------- //

    // Mapping of nftId to nftContractAddress to LoanAuction struct
    mapping(address => mapping(uint256 => LoanAuction)) _loanAuctions;

    mapping(address => mapping(uint256 => OfferBook)) _nftOfferBooks;
    mapping(address => OfferBook) _floorOfferBooks;

    // Cancelled / finalized orders, by signature
    mapping(bytes => bool) _cancelledOrFinalized;

    // fee paid to protocol by borrower for drawing down loan
    // decimal to 10000 because of whole number math
    uint256 public protocolDrawFeePercentage = uint256(1) / 10000;

    // premium paid to current lender by new lender for buying out the loan
    uint256 public refinancePremiumLenderPercentage = uint256(9) / 100000;

    // premium paid to protocol by new lender for buying out the loan
    uint256 public refinancePremiumProtocolPercentage = uint256(1) / 100000;

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
        returns (LoanAuction memory auction)
    {
        auction = _loanAuctions[nftContractAddress][nftId];
    }

    /**
     * @notice Generate a hash of an offer and follow the EIP712
     * @param offer The details of a loan auction offer
     */
    function getOfferHash(Offer memory offer)
        public
        view
        returns (bytes32 offerhash)
    {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        offer.creator,
                        offer.nftContractAddress,
                        offer.nftId,
                        offer.asset,
                        offer.amount,
                        offer.interestRate,
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
    function getSignatureOfferStatus(bytes memory signature)
        external
        view
        returns (bool status)
    {
        status = _cancelledOrFinalized[signature];
    }

    /**
     * @notice Check whether a signature-based offer has been cancelledOrFinalized
     * @param offerHash The hash of all parameters in an offer
     * @param signature A signed offerHash
     */
    //ecrecover the signer from hash and the signature
    function getOfferSigner(
        bytes32 offerHash, //hash of offer
        bytes memory signature //proof the actor signed the offer
    ) public pure returns (address signer) {
        signer = offerHash.toEthSignedMessageHash().recover(signature);
    }

    /**
     * @notice Cancel a signature based offer on chain
     * @dev This function is the only way to ensure an offer can't be used on chain
     * @param offer The details of a loan auction offer
     * @param signature A signed offerHash
     */
    function withdrawBidOrAsk(Offer calldata offer, bytes calldata signature)
        external
    {
        // require signature is still valid. This also ensures the signature is not utilized in an active loan
        require(
            _cancelledOrFinalized[signature] == false,
            "Cannot cancel a bid or ask that is already cancelled or finalized."
        );

        // ideally calculated, stored, and provided as parameter to save computation
        bytes32 offerHash = getOfferHash(offer);

        // recover signer
        address signer = getOfferSigner(offerHash, signature);

        // Require that msg.sender is signer of the signature
        require(
            signer == msg.sender,
            "Msg.sender is not the signer of the submitted signature"
        );

        // cancel signature
        _cancelledOrFinalized[signature] = true;

        emit SigOfferCancelled(
            offer.nftContractAddress,
            offer.nftId,
            signature
        );
    }

    // ---------- On-chain Offer Functions ---------- //

    /**
     * @notice Retreive an offer from the on-chain floor or individual NFT offer books by offerHash identifier
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
    ) external view returns (Offer memory offer) {
        // Offer storage offer;
        OfferBook storage offerBook;

        if (floorTerm == true) {
            offerBook = _floorOfferBooks[nftContractAddress];
            offer = offerBook.offers[offerHash];
        } else if (floorTerm == false) {
            offerBook = _nftOfferBooks[nftContractAddress][nftId];
            offer = offerBook.offers[offerHash];
        }
    }

    /**
     * @notice Retreive an offer from the on-chain floor or individual NFT offer books at a given index
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param index The index at which to retrieve an offer from the OfferBook iterable mapping
     * @param floorTerm Indicates whether this is a floor or individual NFT offer. true = floor offer. false = individual NFT offer
     */
    function getOfferAtIndex(
        address nftContractAddress,
        uint256 nftId,
        uint256 index,
        bool floorTerm
    ) external view returns (Offer memory offer) {
        OfferBook storage offerBook;

        bytes32 offerHash;

        if (floorTerm == true) {
            offerBook = _floorOfferBooks[nftContractAddress];
            offerHash = offerBook.keys[index];
            offer = offerBook.offers[offerHash];
        } else if (floorTerm == false) {
            offerBook = _nftOfferBooks[nftContractAddress][nftId];
            offerHash = offerBook.keys[index];
            offer = offerBook.offers[offerHash];
        }
    }

    /**
     * @notice Retreive the size of the on-chain floor or individual NFT offer book
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param floorTerm Indicates whether to return the floor or individual NFT offer book size. true = floor offer book. false = individual NFT offer book
     */
    function size(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm
    ) external view returns (uint256 offerBookSize) {
        OfferBook storage offerBook;

        if (floorTerm == true) {
            offerBook = _floorOfferBooks[nftContractAddress];
            offerBookSize = offerBook.keys.length;
        } else if (floorTerm == false) {
            offerBook = _nftOfferBooks[nftContractAddress][nftId];
            offerBookSize = offerBook.keys.length;
        }
    }

    /**
     * @notice Create an offer in the on-chain floor offer book
     * @param nftContractAddress The address of the NFT collection
     * @param offer The details of the loan auction floor offer
     */
    function createFloorOffer(address nftContractAddress, Offer memory offer)
        external
    {
        OfferBook storage offerBook = _floorOfferBooks[nftContractAddress];

        offer.creator = msg.sender;
        offer.floorTerm = true;

        bytes32 offerHash = getOfferHash(offer);

        if (offerBook.inserted[offerHash]) {
            offerBook.offers[offerHash] = offer;
        } else {
            offerBook.inserted[offerHash] = true;
            offerBook.offers[offerHash] = offer;
            offerBook.indexOf[offerHash] = offerBook.keys.length;
            offerBook.keys.push(offerHash);
        }

        emit NewOffer(
            offer.creator,
            offer.nftContractAddress,
            offer.nftId,
            offer.asset,
            offer.amount,
            offer.interestRate,
            offer.duration,
            offer.expiration,
            offer.fixedTerms,
            offer.floorTerm,
            offerHash
        );
    }

    /**
     * @notice Create an offer in the on-chain individual NFT offer book
     * @param nftContractAddress The address of the NFT collection
     * @param offer The details of the loan auction individual NFT offer
     */
    function createNftOffer(
        address nftContractAddress,
        uint256 nftId,
        Offer memory offer
    ) external {
        OfferBook storage offerBook = _nftOfferBooks[nftContractAddress][nftId];

        offer.creator = msg.sender;
        offer.floorTerm = false;

        bytes32 offerHash = getOfferHash(offer);

        if (offerBook.inserted[offerHash]) {
            offerBook.offers[offerHash] = offer;
        } else {
            offerBook.inserted[offerHash] = true;
            offerBook.offers[offerHash] = offer;
            offerBook.indexOf[offerHash] = offerBook.keys.length;
            offerBook.keys.push(offerHash);
        }

        emit NewOffer(
            offer.creator,
            offer.nftContractAddress,
            offer.nftId,
            offer.asset,
            offer.amount,
            offer.interestRate,
            offer.duration,
            offer.expiration,
            offer.fixedTerms,
            offer.floorTerm,
            offerHash
        );
    }

    /**
     * @notice Remove an offer in the on-chain floor offer book
     * @param nftContractAddress The address of the NFT collection
     * @param offerHash The hash of all parameters in an offer
     */
    function removeFloorOffer(address nftContractAddress, bytes32 offerHash)
        external
    {
        OfferBook storage offerBook = _floorOfferBooks[nftContractAddress];
        Offer storage offer = offerBook.offers[offerHash];

        require(
            msg.sender == offer.creator,
            "msg.sender is not the offer creator"
        );

        if (!offerBook.inserted[offerHash]) {
            return;
        }

        delete offerBook.inserted[offerHash];
        delete offerBook.offers[offerHash];

        uint256 index = offerBook.indexOf[offerHash];
        uint256 lastIndex = offerBook.keys.length - 1;
        bytes32 lastOfferHash = offerBook.keys[lastIndex];

        offerBook.indexOf[lastOfferHash] = index;
        delete offerBook.indexOf[offerHash];

        offerBook.keys[index] = lastOfferHash;
        offerBook.keys.pop();

        // stack too deep, need to refactor

        // emit OfferRemoved(
        //     offer.creator,
        //     offer.nftContractAddress,
        //     offer.nftId,
        //     offer.asset,
        //     offer.amount,
        //     offer.interestRate,
        //     offer.duration,
        //     offer.expiration,
        //     offer.fixedTerms,
        //     offer.floorTerm,
        //     offerHash
        // );
    }

    /**
     * @notice Remove an offer in the on-chain individual NFT offer book
     * @param nftContractAddress The address of the NFT collection
     * @param offerHash The hash of all parameters in an offer
     */
    function removeNftOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external {
        OfferBook storage offerBook = _nftOfferBooks[nftContractAddress][nftId];
        Offer storage offer = offerBook.offers[offerHash];

        require(
            msg.sender == offer.creator,
            "msg.sender is not the offer creator"
        );

        if (!offerBook.inserted[offerHash]) {
            return;
        }

        delete offerBook.inserted[offerHash];
        delete offerBook.offers[offerHash];

        uint256 index = offerBook.indexOf[offerHash];
        uint256 lastIndex = offerBook.keys.length - 1;
        bytes32 lastOfferHash = offerBook.keys[lastIndex];

        offerBook.indexOf[lastOfferHash] = index;
        delete offerBook.indexOf[offerHash];

        offerBook.keys[index] = lastOfferHash;
        offerBook.keys.pop();

        // stack too deep need to refactor

        // emit OfferRemoved(
        //     offer.creator,
        //     offer.nftContractAddress,
        //     offer.nftId,
        //     offer.asset,
        //     offer.amount,
        //     offer.interestRate,
        //     offer.duration,
        //     offer.expiration,
        //     offer.fixedTerms,
        //     offer.floorTerm,
        //     offerHash
        // );
    }

    // ---------- Execute Loan Functions ---------- //

    /**
     * @notice Allows a borrower to submit a signed offer from a lender and execute a loan using their NFT as collateral
     * @param offer The details of the loan auction offer
     * @param signature A signed offerHash
     * @param nftId The id of a specified NFT
     */
    function sigExecuteLoanByBorrower(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId // nftId should match offer.nftId if offer.floorTerm false, nftId should not match if offer.floorTerm true. Need to provide as function parameter to pass nftId with floor terms.
    ) external payable whenNotPaused nonReentrant {
        // require signature has not been cancelled/bid withdrawn
        require(
            _cancelledOrFinalized[signature] == false,
            "Cannot execute bid or ask. Signature has been cancelled or previously finalized."
        );

        // ideally calculated, stored, and provided as parameter to save computation
        // generate hash of offer parameters
        bytes32 offerHash = getOfferHash(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // we know the signer must be the lender because msg.sender must be the nftOwner/borrower
        address lender = getOfferSigner(offerHash, signature);

        require(
            lender == offer.creator,
            "Offer.creator must be offer signer to executeLoanByBid"
        );

        // // if floorTerm is false
        if (offer.floorTerm == false) {
            // require nftId == sigNftId
            require(
                nftId == offer.nftId,
                "Function submitted nftId must match the signed offer nftId"
            );

            // execute state changes for executeLoanByBid
            _executeLoanByBorrowerInternal(offer, nftId, lender);
        }
        // else if floorTerm is true
        else if (offer.floorTerm == true) {
            // execute state changes for executeLoanByBid
            _executeLoanByBorrowerInternal(offer, nftId, lender);
        }

        // finalize signature
        _cancelledOrFinalized[signature] == true;

        emit SigOfferFinalized(
            offer.nftContractAddress,
            offer.nftId,
            signature
        );
    }

    /**
     * @notice Allows a borrower to submit an offer from the on-chain floor offer book and execute a loan using their NFT as collateral
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
    function chainExecuteLoanByBorrowerFloor(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable whenNotPaused nonReentrant {
        // instantiate Offer Struct
        Offer storage offer = _floorOfferBooks[nftContractAddress].offers[
            offerHash
        ];
        require(offer.floorTerm == true, "Offer must be a floor term");
        _executeLoanByBorrowerInternal(offer, nftId, offer.creator);
    }

    /**
     * @notice Allows a borrower to submit an offer from the on-chain individual NFT offer book and execute a loan using their NFT as collateral
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
    function chainExecuteLoanByBorrowerNft(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable whenNotPaused nonReentrant {
        // instantiate Offer Struct
        Offer storage offer = _nftOfferBooks[nftContractAddress][nftId].offers[
            offerHash
        ];
        require(offer.floorTerm == false, "Offer must be an individual offer");
        require(
            nftId == offer.nftId,
            "Function submitted nftId must match the signed offer nftId"
        );
        _executeLoanByBorrowerInternal(offer, nftId, offer.creator);
    }

    /**
     * @notice handles the checks, state transitions, and value/asset transfers for executeLoanByBorrower
     * @param offer The details of a loan auction offer
     * @param nftId The id of the specified NFT
     * @param lender The prospective lender
     */
    function _executeLoanByBorrowerInternal(
        Offer memory offer,
        uint256 nftId,
        address lender
    ) internal {
        // instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[
            offer.nftContractAddress
        ][nftId];

        address cAsset = assetToCAsset[offer.asset];

        // require offer has not expired
        require(
            offer.expiration > block.timestamp,
            "Cannot execute bid, offer has expired"
        );

        // require offer has 24 hour minimum duration
        require(
            offer.duration >= 86400,
            "Offers must have 24 hours minimum duration"
        );

        require(
            assetToCAsset[offer.asset] !=
                0x0000000000000000000000000000000000000000,
            "Asset not whitelisted on NiftyApes"
        );

        // get nft owner
        address nftOwner = IERC721(offer.nftContractAddress).ownerOf(nftId);

        // require msg.sender is the nftOwner. This ensures function submitted nftId is valid to execute against
        // this also provides a check for floor term offers that the msg.sender owns an asset in the collection
        require(
            nftOwner == msg.sender,
            "Msg.sender must be the owner of nftId to executeLoanByBid"
        );

        // Require that loan is not active
        require(
            loanAuction.loanExecutedTime == 0,
            "Loan is already active. Please use refinanceByBorrower()"
        );

        // check if lender has sufficient available balance and update utilizedBalance
        _checkAndUpdateLenderUtilizedBalanceInternal(
            cAsset,
            offer.amount,
            lender
        );

        // update loanAuction struct
        loanAuction.nftOwner = nftOwner;
        loanAuction.lender = lender;
        loanAuction.asset = offer.asset;
        loanAuction.amount = offer.amount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.duration = offer.duration;
        loanAuction.timeOfInterestStart = block.timestamp;
        loanAuction.loanExecutedTime = block.timestamp;
        loanAuction.timeDrawn = offer.duration;
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;

        // *------- value and asset transfers -------* //

        // transferFrom NFT from nftOwner to contract
        IERC721(offer.nftContractAddress).transferFrom(
            nftOwner,
            address(this),
            nftId
        );

        // if asset is not 0x0 process as Erc20
        if (
            offer.asset != address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferErc20Internal(
                offer.asset,
                cAsset,
                offer.amount,
                nftOwner
            );
        }
        // else process as ETH
        else if (
            offer.asset == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferEthInternal(cAsset, offer.amount, nftOwner);
        }

        emit LoanExecuted(
            lender,
            nftOwner,
            offer.nftContractAddress,
            offer.nftId,
            offer.asset,
            offer.amount,
            offer.interestRate,
            offer.duration
        );
    }

    /**
     * @notice Allows a lender to submit a signed offer from a borrower and execute a loan using the borrower's NFT as collateral
     * @param offer The details of the loan auction offer
     * @param signature A signed offerHash
     */
    function sigExecuteLoanByLender(
        Offer calldata offer,
        bytes calldata signature
    ) external payable whenNotPaused nonReentrant {
        // require signature has not been cancelled/bid withdrawn
        require(
            _cancelledOrFinalized[signature] == false,
            "Cannot execute bid or ask. Signature has been cancelled or previously finalized."
        );

        bytes32 offerHash = getOfferHash(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // We assume the signer is the borrower and check in the following require statment
        address borrower = getOfferSigner(offerHash, signature);

        // execute state changes for executeLoanByAsk
        _executeLoanByLenderInternal(offer, msg.sender, borrower);

        // finalize signature
        _cancelledOrFinalized[signature] == true;

        emit SigOfferFinalized(
            offer.nftContractAddress,
            offer.nftId,
            signature
        );
    }

    /**
     * @notice Allows a lender to submit an offer from the borrower in the on-chain individual NFT offer book and execute a loan using the borrower's NFT as collateral
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
    function chainExecuteLoanByLender(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) public payable whenNotPaused nonReentrant {
        // instantiate LoanAuction Struct
        Offer storage offer = _nftOfferBooks[nftContractAddress][nftId].offers[
            offerHash
        ];

        // execute state changes for executeLoanByAsk
        _executeLoanByLenderInternal(offer, msg.sender, offer.creator);
    }

    /**
     * @notice Handles checks, state transitions, and value/asset transfers for executeLoanbyLender
     * @param offer The details of a loan auction offer
     * @param lender The prospective lender
     * @param borrower The prospective borrower and owner of the NFT
     */
    function _executeLoanByLenderInternal(
        Offer memory offer,
        address lender,
        address borrower
    ) internal {
        // instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[
            offer.nftContractAddress
        ][offer.nftId];

        address cAsset = assetToCAsset[offer.asset];

        // *------------ Checks ------------* //

        // require loan is not active
        require(
            loanAuction.loanExecutedTime == 0,
            "Loan is already active. Please use refinanceByLender()"
        );

        require(
            assetToCAsset[offer.asset] != address(0),
            "Asset not whitelisted on NiftyApes"
        );

        // require offer has not expired
        require(
            offer.expiration > block.timestamp,
            "Cannot execute bid, offer has expired"
        );

        // require offer has 24 hour minimum duration
        require(
            offer.duration >= 86400,
            "Offers must have 24 hours minimum duration"
        );

        // get nft owner
        address nftOwner = IERC721(offer.nftContractAddress).ownerOf(
            offer.nftId
        );

        require(
            borrower == nftOwner,
            "Borrower must be the owner of nftId to executeLoanByLender"
        );

        // *------------ State Transitions ------------* //

        // check if lender has sufficient available balance and update utilizedBalance
        _checkAndUpdateLenderUtilizedBalanceInternal(
            cAsset,
            offer.amount,
            lender
        );

        // update LoanAuction struct
        loanAuction.nftOwner = borrower;
        loanAuction.lender = lender;
        loanAuction.asset = offer.asset;
        loanAuction.amount = offer.amount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.duration = offer.duration;
        loanAuction.timeOfInterestStart = block.timestamp;
        loanAuction.loanExecutedTime = block.timestamp;
        loanAuction.timeDrawn = offer.duration;
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;

        // *------- Value and asset transfers -------* //

        // transferFrom NFT from borrower to contract
        IERC721(offer.nftContractAddress).transferFrom(
            borrower,
            address(this),
            offer.nftId
        );

        // Process as ETH
        if (
            offer.asset == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferEthInternal(cAsset, offer.amount, borrower);
        }
        // Process as ERC20
        else {
            _redeemAndTransferErc20Internal(
                offer.asset,
                cAsset,
                offer.amount,
                borrower
            );
        }

        emit LoanExecuted(
            lender,
            borrower,
            offer.nftContractAddress,
            offer.nftId,
            offer.asset,
            offer.amount,
            offer.interestRate,
            offer.duration
        );
    }

    // ---------- Refinance Loan Functions ---------- //

    /**
     * @notice Allows a borrower to submit a signed offer from a lender and refinance a loan with near arbitrary terms
     * @dev The offer amount must be greater than the current loan amount plus interest owed to the lender
     * @param offer The details of the loan auction offer
     * @param signature A signed offerHash
     * @param nftId The id of a specified NFT
     */
    function sigRefinanceByBorrower(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId
    ) external payable whenNotPaused nonReentrant {
        // ideally calculated, stored, and provided as parameter to save computation
        bytes32 offerHash = getOfferHash(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // We assume the signer is the lender because msg.sender must the the nftOwner
        address prospectiveLender = getOfferSigner(offerHash, signature);

        require(
            offer.creator == prospectiveLender,
            "Signer must be the offer.creator"
        );

        if (offer.floorTerm == false) {
            // require nftId == sigNftId
            require(
                nftId == offer.nftId,
                "Function submitted nftId must match the signed offer nftId"
            );

            // execute state changes for executeLoanByBid
            _refinanceByBorrowerInternal(offer, offer.creator, nftId);
        }
        // if floorTerm is true
        else if (offer.floorTerm == true) {
            // execute state changes for executeLoanByBid
            _refinanceByBorrowerInternal(offer, offer.creator, nftId);
        }
    }

    /**
     * @notice Allows a borrower to submit an offer from the on-chain floor offer book and refinance a loan with near arbitrary terms
     * @dev The offer amount must be greater than the current loan amount plus interest owed to the lender
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
    function chainRefinanceByBorrowerFloor(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable whenNotPaused nonReentrant {
        Offer storage offer = _floorOfferBooks[nftContractAddress].offers[
            offerHash
        ];
        require(offer.floorTerm == true, "Offer must be a floor term");
        _refinanceByBorrowerInternal(offer, offer.creator, nftId);
    }

    /**
     * @notice Allows a borrower to submit an offer from the on-chain individual NFT offer book and refinance a loan with near arbitrary terms
     * @dev The offer amount must be greater than the current loan amount plus interest owed to the lender
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
    function chainRefinanceByBorrowerNft(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable whenNotPaused nonReentrant {
        Offer storage offer = _floorOfferBooks[nftContractAddress].offers[
            offerHash
        ];
        require(offer.floorTerm == false, "Offer must be an individual offer");
        require(
            nftId == offer.nftId,
            "Function submitted nftId must match the signed offer nftId"
        );
        _refinanceByBorrowerInternal(offer, offer.creator, nftId);
    }

    /**
     * @notice Handles checks, state transitions, and value/asset transfers for executeLoanbyLender
     * @param offer The details of a loan auction offer
     * @param prospectiveLender The prospective lender
     * @param nftId The id of the specified NFT
     */
    function _refinanceByBorrowerInternal(
        Offer memory offer,
        address prospectiveLender,
        uint256 nftId
    ) internal {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[
            offer.nftContractAddress
        ][nftId];

        address cAsset = assetToCAsset[loanAuction.asset];

        // Require that loan does not have fixedTerms
        require(
            loanAuction.fixedTerms != true,
            "Loan has fixedTerms cannot refinanceBestOffer."
        );

        // Require that loan is active
        require(
            loanAuction.loanExecutedTime != 0,
            "Loan is not active. No funds to withdraw. Please use executeLoanByBid()"
        );

        // require offer is same asset and cAsset
        require(
            offer.asset == loanAuction.asset,
            "Offer asset and cAsset must be the same as the current loan"
        );

        // Require that loan has not expired
        require(
            block.timestamp <
                loanAuction.loanExecutedTime + loanAuction.timeDrawn,
            "Cannot refinance loan that has expired"
        );

        // get nft owner
        address nftOwner = IERC721(offer.nftContractAddress).ownerOf(nftId);

        // require msg.sender is the nftOwner/borrower
        require(
            nftOwner == msg.sender,
            "Msg.sender must be the owner of nftId to refinanceByBorrower"
        );

        // calculate the interest earned by current lender
        uint256 lenderInterest = calculateInterestAccrued(
            offer.nftContractAddress,
            nftId,
            true
        );

        // need to ensure protocol fee is calculated correctly here. Interest is paid by new ledner, should protocol fee be as well?

        // calculate the interest earned by protocol
        uint256 currentProtocolInterest = calculateInterestAccrued(
            offer.nftContractAddress,
            offer.nftId,
            false
        );

        // calculate interest earned
        uint256 interestOwedToLender = lenderInterest +
            loanAuction.historicLenderInterest;

        uint256 fullRepayment = loanAuction.amountDrawn + interestOwedToLender;

        // require statement for offer amount to be greater than or equal to full repayment
        require(
            offer.amount >= fullRepayment,
            "Offer amount must be greater than or equal to current amount drawn + interest owed"
        );

        require(
            (cAssetBalances[cAsset][prospectiveLender] -
                utilizedCAssetBalances[cAsset][prospectiveLender]) >=
                fullRepayment,
            "Prospective lender does not have sufficient balance to buy out loan"
        );

        // processes cEth and ICERC20 transactions
        _transferICERC20BalancesInternal(
            cAsset,
            loanAuction.lender,
            prospectiveLender,
            0,
            interestOwedToLender,
            loanAuction.amountDrawn
        );

        uint256 currentHistoricProtocolInterest = loanAuction
            .historicProtocolInterest;

        // update LoanAuction struct
        loanAuction.lender = prospectiveLender;
        loanAuction.amount = offer.amount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.duration = offer.duration;
        loanAuction.amountDrawn = fullRepayment;
        loanAuction.timeOfInterestStart = block.timestamp;
        loanAuction.historicLenderInterest = 0;
        loanAuction.historicProtocolInterest =
            currentHistoricProtocolInterest +
            currentProtocolInterest;

        // stack too deep for these event variables, need to refactor
        // emit LoanRefinance(
        //     lender,
        //     nftOwner,
        //     offer.nftContractAddress,
        //     offer.nftId,
        //     offer.asset,
        //     offer.amount,
        //     offer.interestRate,
        //     offer.duration
        // );

        // emit SigOfferFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    /**
     * @notice Allows a lender offer better terms than the current loan, refinance, and take over a loan
     * @dev The offer amount, interest rate, and duration must be at parity with the current loan, plus "1". Meaning at least one term must be better than the current loan.
     * @dev new lender balance must be sufficient to pay fullRefinance amount
     * @dev current lender balance must be sufficient to fund new offer amount
     * @param offer The details of the loan auction offer
     */
    function refinanceByLender(Offer calldata offer)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[
            offer.nftContractAddress
        ][offer.nftId];

        address cAsset = assetToCAsset[loanAuction.asset];

        // Require that loan does not have fixedTerms
        require(
            loanAuction.fixedTerms != true,
            "Loan has fixedTerms cannot refinanceBestOffer."
        );

        // Require that loan is active
        require(
            loanAuction.loanExecutedTime != 0,
            "Loan is not active. No funds to withdraw. Please use executLoanByAsk()"
        );

        // require offer is same asset
        require(
            offer.asset == loanAuction.asset,
            "Offer asset must be the same as the current loan"
        );

        require(
            block.timestamp <
                loanAuction.loanExecutedTime + loanAuction.timeDrawn,
            "Cannot refinance loan that has expired"
        );

        // require that terms are parity + 1
        require(
            // Require bidAmount is greater than previous bid
            (offer.amount > loanAuction.amount &&
                offer.interestRate <= loanAuction.interestRate &&
                offer.duration >= loanAuction.duration) ||
                // OR
                // Require interestRate is lower than previous bid
                (offer.amount >= loanAuction.amount &&
                    offer.interestRate < loanAuction.interestRate &&
                    offer.duration >= loanAuction.duration) ||
                // OR
                // Require duration to be greater than previous bid
                (offer.amount >= loanAuction.amount &&
                    offer.interestRate <= loanAuction.interestRate &&
                    offer.duration > loanAuction.duration),
            "Bid must have better terms than current loan"
        );

        // if duration is the only term updated
        if (
            offer.amount == loanAuction.amount &&
            offer.interestRate == loanAuction.interestRate &&
            offer.duration > loanAuction.duration
        ) {
            // require offer has at least 24 hour additional duration
            require(
                offer.duration >= (loanAuction.duration + 86400),
                "Cannot refinanceBestOffer. Offer duration must be at least 24 hours greater than current loan. "
            );
        }

        // calculate the interest earned by current lender
        uint256 currentLenderInterest = calculateInterestAccrued(
            offer.nftContractAddress,
            offer.nftId,
            true
        );

        // calculate the interest earned by protocol
        uint256 currentProtocolInterest = calculateInterestAccrued(
            offer.nftContractAddress,
            offer.nftId,
            false
        );

        // calculate interest earned
        uint256 interestAndPremiumOwedToCurrentLender = currentLenderInterest +
            loanAuction.historicLenderInterest +
            (loanAuction.amountDrawn * refinancePremiumLenderPercentage);

        // calculate fullRefinanceAmount
        uint256 fullRefinanceAmount = interestAndPremiumOwedToCurrentLender +
            loanAuction.amountDrawn;

        // If refinancing is not done by current lender they must buy out the loan and pay fees
        if (loanAuction.lender != msg.sender) {
            // require prospective lender has sufficient available balance to refinance loan
            require(
                (cAssetBalances[cAsset][msg.sender] -
                    utilizedCAssetBalances[cAsset][msg.sender]) >=
                    fullRefinanceAmount,
                "Prospective lender does not have sufficient balance to refinance loan"
            );

            // processes cEth and ICERC20 transactions
            _transferICERC20BalancesInternal(
                cAsset,
                loanAuction.lender,
                msg.sender,
                0,
                interestAndPremiumOwedToCurrentLender,
                loanAuction.amountDrawn
            );

            // update LoanAuction lender
            loanAuction.lender = msg.sender;

            // If current lender is refinancing the loan they do not need to pay any fees or buy themselves out.
        } else if (loanAuction.lender == msg.sender) {
            // check this require statment, might be duplictive to ofer checks above.

            require(
                (cAssetBalances[cAsset][msg.sender] -
                    utilizedCAssetBalances[cAsset][msg.sender]) >=
                    offer.amount - loanAuction.amountDrawn,
                "Lender does not have sufficient balance to refinance loan"
            );
        }

        // need to ensure protocol interest is paid correctly in interal functions

        // save temporary current historicLenderInterest
        uint256 currentHistoricLenderInterest = loanAuction
            .historicLenderInterest;
        uint256 currentHistoricProtocolInterest = loanAuction
            .historicProtocolInterest;

        // update LoanAuction struct
        loanAuction.amount = offer.amount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.duration = offer.duration;
        loanAuction.timeOfInterestStart = block.timestamp;
        loanAuction.historicLenderInterest =
            currentHistoricLenderInterest +
            currentLenderInterest;
        loanAuction.historicProtocolInterest =
            currentHistoricProtocolInterest +
            currentProtocolInterest;

        // need to ensure event tracks protocolPremiumAmount so that we can accurately account funds to allocate to Regen Collective
        // stack too deep problem, need to refactor
        // emit LoanRefinance(
        //     msg.sender,
        //     loanAuction.nftOwner,
        //     offer.nftContractAddress,
        //     offer.nftId,
        //     offer.asset,
        //     offer.amount,
        //     offer.interestRate,
        //     offer.duration
        // );
    }

    // ---------- Borrower Draw Functions ---------- //

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
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][
            nftId
        ];

        // Require that loan is active
        require(
            loanAuction.loanExecutedTime != 0,
            "Loan is not active. No funds to withdraw."
        );

        // Require msg.sender is the nftOwner on the nft contract
        require(
            msg.sender == loanAuction.nftOwner,
            "Msg.sender is not the NFT owner"
        );

        // document that a user CAN draw more time after a loan has expired, but they are still open to asset siezure until they draw enough time.
        // // Require that loan has not expired
        // require(
        //     block.timestamp <
        //         loanAuction.loanExecutedTime + loanAuction.timeDrawn,
        //     "Cannot draw more time after a loan has expired"
        // );

        // Require timeDrawn is less than the duration. Ensures there is time available to draw
        require(
            loanAuction.timeDrawn < loanAuction.duration,
            "Draw Time amount not available"
        );

        // Require that drawTime + timeDrawn does not exceed duration
        require(
            (drawTime + loanAuction.timeDrawn) <= loanAuction.duration,
            "Total Time drawn must not exceed best bid duration"
        );

        uint256 lenderInterest = calculateInterestAccrued(
            nftContractAddress,
            nftId,
            true
        );

        uint256 protocolInterest = calculateInterestAccrued(
            nftContractAddress,
            nftId,
            false
        );

        // reset timeOfinterestStart and update historic interest due to parameters of loan changing
        loanAuction.historicLenderInterest += lenderInterest;
        loanAuction.historicProtocolInterest += protocolInterest;
        loanAuction.timeOfInterestStart = block.timestamp;

        // set timeDrawn
        loanAuction.timeDrawn += drawTime;

        emit TimeDrawn(
            nftContractAddress,
            nftId,
            drawTime,
            loanAuction.timeDrawn
        );
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
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][
            nftId
        ];

        address cAsset = assetToCAsset[loanAuction.asset];

        // Require that loan is active
        require(
            loanAuction.loanExecutedTime != 0,
            "Loan is not active. No funds to withdraw."
        );

        // Require msg.sender is the borrower
        require(
            msg.sender == loanAuction.nftOwner,
            "Msg.sender is not the NFT owner"
        );

        // Require amountDrawn is less than the bestOfferAmount
        require(
            loanAuction.amountDrawn < loanAuction.amount,
            "Draw down amount not available"
        );

        // Require that drawAmount does not exceed amount
        require(
            (drawAmount + loanAuction.amountDrawn) <= loanAuction.amount,
            "Total amount withdrawn must not exceed best bid loan amount"
        );

        // Require that loan has not expired
        require(
            block.timestamp <
                loanAuction.loanExecutedTime + loanAuction.timeDrawn,
            "Cannot draw more value after a loan has expired"
        );

        _checkAndUpdateLenderUtilizedBalanceInternal(
            cAsset,
            drawAmount,
            loanAuction.lender
        );

        uint256 lenderInterest = calculateInterestAccrued(
            nftContractAddress,
            nftId,
            true
        );

        uint256 protocolInterest = calculateInterestAccrued(
            nftContractAddress,
            nftId,
            false
        );

        // reset timeOfinterestStart and update historic interest due to parameters of loan changing
        loanAuction.historicLenderInterest += lenderInterest;
        loanAuction.historicProtocolInterest += protocolInterest;
        loanAuction.timeOfInterestStart = block.timestamp;

        // set amountDrawn
        loanAuction.amountDrawn += drawAmount;

        // if asset is not 0x0 process as Erc20
        if (
            loanAuction.asset !=
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferErc20Internal(
                loanAuction.asset,
                cAsset,
                drawAmount,
                loanAuction.nftOwner
            );
        }
        // else process as ETH
        else if (
            loanAuction.asset ==
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferEthInternal(
                cAsset,
                drawAmount,
                loanAuction.nftOwner
            );
        }

        emit AmountDrawn(
            nftContractAddress,
            nftId,
            drawAmount,
            loanAuction.amountDrawn
        );
    }

    // ---------- Repayment and Asset Seizure Functions ---------- //

    /**
     * @notice Enables a borrower to repay the remaining value of their loan plus interest and protocol fee, and regain full ownership of their NFT
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     */
    function repayRemainingLoan(address nftContractAddress, uint256 nftId)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][
            nftId
        ];

        address cAsset = assetToCAsset[loanAuction.asset];

        // Require that loan has been executed
        require(
            loanAuction.loanExecutedTime != 0,
            "Cannot repay loan that has not been executed"
        );

        // Require msg.sender is the borrower
        require(
            msg.sender == loanAuction.nftOwner,
            "Msg.sender is not the NFT owner"
        );

        // calculate the amount of interest accrued by the lender
        uint256 lenderInterest = calculateInterestAccrued(
            nftContractAddress,
            nftId,
            true
        );

        // calculate the amount of interest accrued by the lender
        uint256 protocolInterest = calculateInterestAccrued(
            nftContractAddress,
            nftId,
            false
        );

        // calculate total interest value owed
        uint256 interestOwedToLender = lenderInterest +
            loanAuction.historicLenderInterest;

        // need to ensure protocol is being paid out correctly

        // calculate total interest value owed
        uint256 interestOwedToProtocol = protocolInterest +
            loanAuction.historicProtocolInterest;

        // get required repayment
        uint256 fullRepayment = interestOwedToLender +
            interestOwedToProtocol +
            loanAuction.amountDrawn;

        address currentAsset = loanAuction.asset;
        address currentLender = loanAuction.lender;
        uint256 currentAmountDrawn = loanAuction.amountDrawn;

        // reset loanAuction
        loanAuction.nftOwner = address(0);
        loanAuction.lender = address(0);
        loanAuction.asset = address(0);
        loanAuction.amount = 0;
        loanAuction.interestRate = 0;
        loanAuction.duration = 0;
        loanAuction.loanExecutedTime = 0;
        loanAuction.timeOfInterestStart = 0;
        loanAuction.historicLenderInterest = 0;
        loanAuction.historicLenderInterest = 0;
        loanAuction.amountDrawn = 0;
        loanAuction.timeDrawn = 0;
        loanAuction.fixedTerms = false;

        // if asset is not 0x0 process as Erc20
        if (
            currentAsset != address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // protocolPremiumFee is taken here. Full amount is minted to this contract address' balance in Compound and amount owed to lender is updated in their balance. The delta is the protocol premium fee.
            _payErc20AndUpdateBalancesInternal(
                currentAsset,
                cAsset,
                currentLender,
                msg.sender,
                fullRepayment,
                interestOwedToLender,
                currentAmountDrawn
            );
        }
        // else process as ETH
        else if (
            currentAsset == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // check that transaction covers the full value of the loan
            require(
                msg.value >= fullRepayment,
                "Must repay full amount of loan drawn plus interest and fee. Account for additional time for interest."
            );
            // protocolPremiumFee is taken here. Full amount is minted to this contract address' balance in Compound and amount owed to lender is updated in their balance. The delta is the protocol premium fee.
            _payEthAndUpdateBalancesInternal(
                cAsset,
                currentLender,
                msg.value,
                msg.value,
                interestOwedToLender,
                currentAmountDrawn
            );
        }

        // transferFrom NFT from contract to nftOwner
        IERC721(nftContractAddress).transferFrom(
            address(this),
            msg.sender,
            nftId
        );

        emit LoanRepaidInFull(nftContractAddress, nftId);

        return 0;
    }

    /**
     * @notice Allows borrowers to make a partial payment toward the principle of their loan
     * @dev This function does not charge any interest or fees. It does change the calculation for future interest and fees accrual, so we track historicLenderInterest and historicProtocolInterest
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param partialAmount The amount of value to pay down on the principle of the loan
     */
    function partialPayment(
        address nftContractAddress,
        uint256 nftId,
        uint256 partialAmount
    ) external payable whenNotPaused nonReentrant {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][
            nftId
        ];

        address cAsset = assetToCAsset[loanAuction.asset];

        // Require that loan has been executed
        require(
            loanAuction.loanExecutedTime != 0,
            "Cannot repay loan that has not been executed"
        );

        // Require msg.sender is the borrower
        require(
            msg.sender == loanAuction.nftOwner,
            "Msg.sender is not the NFT owner"
        );

        // calculate the amount of interest accrued by the lender
        uint256 lenderInterest = calculateInterestAccrued(
            nftContractAddress,
            nftId,
            true
        );

        uint256 protocolInterest = calculateInterestAccrued(
            nftContractAddress,
            nftId,
            false
        );

        loanAuction.historicLenderInterest += lenderInterest;
        loanAuction.historicProtocolInterest += protocolInterest;
        loanAuction.timeOfInterestStart = block.timestamp;

        uint256 currentAmountDrawn = loanAuction.amountDrawn;
        // update amountDrawn
        loanAuction.amountDrawn -= partialAmount;

        // if asset is not 0x0 process as Erc20
        if (
            loanAuction.asset !=
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            require(
                partialAmount < currentAmountDrawn,
                "Msg.value must be less than amountDrawn"
            );

            _payErc20AndUpdateBalancesInternal(
                loanAuction.asset,
                cAsset,
                loanAuction.lender,
                msg.sender,
                partialAmount,
                0,
                partialAmount
            );
        }
        // else process as ETH
        else if (
            loanAuction.asset ==
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // check that transaction covers the full value of the loan
            require(
                msg.value < currentAmountDrawn,
                "Msg.value must be less than amountDrawn"
            );

            _payEthAndUpdateBalancesInternal(
                cAsset,
                loanAuction.lender,
                msg.value,
                msg.value,
                0,
                partialAmount
            );
        }

        emit PartialRepayment(
            nftContractAddress,
            nftId,
            loanAuction.asset,
            partialAmount
        );
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
        // instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][
            nftId
        ];

        address cAsset = assetToCAsset[loanAuction.asset];

        // require that loan has been executed
        require(
            loanAuction.loanExecutedTime != 0,
            "Cannot seize asset for loan that has not been executed"
        );

        // require that loan has expired
        require(
            block.timestamp >=
                loanAuction.loanExecutedTime + loanAuction.timeDrawn,
            "Cannot seize asset before the end of the loan"
        );

        // temporarily save current lender
        address currentlender = loanAuction.lender;

        // reset loanAuction
        loanAuction.nftOwner = address(0);
        loanAuction.lender = address(0);
        loanAuction.asset = address(0);
        loanAuction.amount = 0;
        loanAuction.interestRate = 0;
        loanAuction.duration = 0;
        loanAuction.timeOfInterestStart = 0;
        loanAuction.loanExecutedTime = 0;
        loanAuction.historicLenderInterest = 0;
        loanAuction.amountDrawn = 0;
        loanAuction.timeDrawn = 0;
        loanAuction.fixedTerms = false;

        // update lenders utilized balance
        utilizedCAssetBalances[cAsset][loanAuction.lender] -= loanAuction
            .amountDrawn;

        // update lenders total balance
        cAssetBalances[cAsset][loanAuction.lender] -= loanAuction.amountDrawn;

        // transferFrom NFT from contract to lender
        IERC721(nftContractAddress).transferFrom(
            address(this),
            currentlender,
            nftId
        );

        emit AssetSeized(nftContractAddress, nftId);
    }

    // ---------- Internal Payment, Balance, and Transfer Functions ---------- //


    function _checkAndUpdateLenderUtilizedBalanceInternal(
        address cAsset,
        uint256 amount,
        address lender
    ) internal returns (uint256) {
        // create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // instantiate RedeemLocalVars
        RedeemLocalVars memory vars;

        // set exchangeRate of erc20 to ICERC20
        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        // convert amount to ICERC20
        (vars.mathErr, vars.redeemTokens) = divScalarByExpTruncate(
            amount,
            Exp({mantissa: vars.exchangeRateMantissa})
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                    uint256(vars.mathErr)
                );
        }

        // require that the lenders available balance is sufficent to serve the loan
        require(
            // calculate lenders available ICERC20 balance and require it to be greater than or equal to vars.redeemTokens
            (cAssetBalances[cAsset][lender] -
                utilizedCAssetBalances[cAsset][lender]) >= vars.redeemTokens,
            "Lender does not have a sufficient balance to serve this loan"
        );

        // update the lenders utilized balance
        utilizedCAssetBalances[cAsset][lender] += vars.redeemTokens;

        return 0;
    }

    // this internal functions handles transfer of erc20 tokens and updating lender balances for refinanceLoan, repayRemainingLoan, and partialRepayment functions
    function _payErc20AndUpdateBalancesInternal(
        address asset,
        address cAsset,
        address to,
        address from,
        uint256 fullAmount,
        uint256 interestAndPremiumAmount,
        uint256 paymentAmount
    ) internal returns (uint256) {
        // Create a reference to the underlying asset contract, like DAI.
        IERC20 underlying = IERC20(asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // instantiate interestAndPremiumTokens
        uint256 interestAndPremiumTokens;
        // instantiate paymentTokens
        uint256 paymentTokens;

        // should have require statement to ensure tranfer is successful before proceeding
        // transferFrom ERC20 from depositors address
        underlying.transferFrom(from, address(this), fullAmount);

        // instantiate MintLocalVars
        MintLocalVars memory vars;

        // set exchange rate from erc20 to ICERC20
        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        // convert interestAndPremiumAmount to ICERC20
        (vars.mathErr, interestAndPremiumTokens) = divScalarByExpTruncate(
            interestAndPremiumAmount,
            Exp({mantissa: vars.exchangeRateMantissa})
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                    uint256(vars.mathErr)
                );
        }

        // convert paymentAmount to ICERC20
        (vars.mathErr, paymentTokens) = divScalarByExpTruncate(
            paymentAmount,
            Exp({mantissa: vars.exchangeRateMantissa})
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                    uint256(vars.mathErr)
                );
        }

        // should have require statement to ensure mint is successful before proceeding
        // protocolDrawFee is taken here as the fullAmount will be greater the paymentTokens + interestAndPremiumTokens and remain at the NA contract address
        // mint cTokens
        cToken.mint(fullAmount);

        // update the tos utilized balance
        utilizedCAssetBalances[cAsset][to] -= paymentTokens;

        // update the tos total balance
        cAssetBalances[cAsset][to] += interestAndPremiumTokens;

        return 0;
    }

    // this internal functions handles transfer of Eth and updating lender balances for refinanceLoan, repayRemainingLoan, and partialRepayment functions
    function _payEthAndUpdateBalancesInternal(
        address cAsset,
        address to,
        uint256 msgValue,
        uint256 msgValueMinusFee,
        uint256 interestAndPremiumAmount,
        uint256 paymentAmount
    ) internal returns (uint256) {
        // Create a reference to the corresponding cToken contract, like cDAI
        ICEther cToken = ICEther(cAsset);

        // instantiate interestAndPremiumTokens
        uint256 interestAndPremiumTokens;
        // instantiate paymentTokens
        uint256 paymentTokens;
        // instantiate msgValueTokens
        uint256 msgValueTokens;

        //Instantiate MintLocalVars
        MintLocalVars memory vars;

        // set exchange rate from eth to ICERC20
        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        // convert msgValueMinusFee to ICERC20
        // This accounts for any extra Eth sent to function, since cant use transferFrom for exact amount
        // Any extra value is given to to
        (vars.mathErr, msgValueTokens) = divScalarByExpTruncate(
            msgValueMinusFee,
            Exp({mantissa: vars.exchangeRateMantissa})
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                    uint256(vars.mathErr)
                );
        }

        // convert interestAndPremiumAmount to ICERC20
        (vars.mathErr, interestAndPremiumTokens) = divScalarByExpTruncate(
            interestAndPremiumAmount,
            Exp({mantissa: vars.exchangeRateMantissa})
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                    uint256(vars.mathErr)
                );
        }

        // convert paymentAmount to ICERC20
        (vars.mathErr, paymentTokens) = divScalarByExpTruncate(
            paymentAmount,
            Exp({mantissa: vars.exchangeRateMantissa})
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                    uint256(vars.mathErr)
                );
        }

        uint256 mintDelta = msgValueTokens -
            (interestAndPremiumTokens + paymentTokens);

        // should have require statement to ensure mint is successful before proceeding
        // // mint CEth tokens to this contract address
        cToken.mint{value: msgValue, gas: 250000}();

        // update the to's utilized balance
        utilizedCAssetBalances[cAsset][to] -= paymentTokens;

        // update the to's total balance
        cAssetBalances[cAsset][to] += (interestAndPremiumTokens + mintDelta);

        return 0;
    }

    // this internal functions handles transfer of erc20 tokens for executeLoan functions
    function _redeemAndTransferErc20Internal(
        address asset,
        address cAsset,
        uint256 amount,
        address nftOwner
    ) internal {
        // Create a reference to the underlying asset contract, like DAI.
        IERC20 underlying = IERC20(asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // redeem underlying from cToken to this contract
        cToken.redeemUnderlying(amount);

        // transfer underlying from this contract to borrower
        underlying.transfer(nftOwner, amount);
    }

    // this internal functions handles transfer of eth for executeLoan functions
    function _redeemAndTransferEthInternal(
        address cAsset,
        uint256 amount,
        address nftOwner
    ) internal {
        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // redeem underlying from cToken to this contract
        require(
            cToken.redeemUnderlying(amount) == 0,
            "cToken.redeemUnderlying() failed"
        );

        // Send Eth to borrower
        (bool success, ) = (nftOwner).call{value: amount}("");
        require(success, "Send eth to depositor failed");
    }

    function _transferICERC20BalancesInternal(
        address cAsset,
        address to,
        address from,
        uint256 protocolPremiumFee,
        uint256 interestAndPremiumAmount,
        uint256 paymentAmount
    ) internal returns (uint256) {
        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // instantiate protocolPremiumFeeTokens
        uint256 protocolPremiumFeeTokens;
        // instantiate interestAndPremiumTokens
        uint256 interestAndPremiumTokens;
        // instantiate paymentTokens
        uint256 paymentTokens;

        // instantiate MintLocalVars
        MintLocalVars memory vars;

        // set exchange rate from erc20 to ICERC20
        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        // convert protocolPremiumFeeTokens to ICERC20
        (vars.mathErr, protocolPremiumFeeTokens) = divScalarByExpTruncate(
            protocolPremiumFee,
            Exp({mantissa: vars.exchangeRateMantissa})
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                    uint256(vars.mathErr)
                );
        }

        // convert interestAndPremiumAmount to ICERC20
        (vars.mathErr, interestAndPremiumTokens) = divScalarByExpTruncate(
            interestAndPremiumAmount,
            Exp({mantissa: vars.exchangeRateMantissa})
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                    uint256(vars.mathErr)
                );
        }

        // convert paymentAmount to ICERC20
        (vars.mathErr, paymentTokens) = divScalarByExpTruncate(
            paymentAmount,
            Exp({mantissa: vars.exchangeRateMantissa})
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                    uint256(vars.mathErr)
                );
        }

        // check calling functions require from has a sufficient total balance to buy out loan

        // update from's utilized balance
        utilizedCAssetBalances[cAsset][from] += paymentTokens;

        // update from's total balance
        cAssetBalances[cAsset][from] -= protocolPremiumFeeTokens;

        // update the to's utilized balance
        utilizedCAssetBalances[cAsset][to] -= paymentTokens;

        // update the to's total balance
        cAssetBalances[cAsset][to] += interestAndPremiumTokens;

        return 0;
    }

    // ---------- Helper Functions ---------- //

    // returns the owner of an NFT the has a loan against it
    function ownerOf(address nftContractAddress, uint256 nftId)
        external
        view
        returns (address)
    {
        // instantiate LoanAuction Struct
        LoanAuction memory loanAuction = _loanAuctions[nftContractAddress][
            nftId
        ];

        return loanAuction.nftOwner;
    }

    // returns the interest value earned by lender or protocol during timeOfInterest segment
    function calculateInterestAccrued(
        address nftContractAddress,
        uint256 nftId,
        // true for lender, false for protocol
        bool lenderOrProtocol
    ) public view returns (uint256) {
        // instantiate LoanAuction Struct
        LoanAuction memory loanAuction = _loanAuctions[nftContractAddress][
            nftId
        ];

        // Require that loan is active
        require(
            loanAuction.loanExecutedTime != 0,
            "Loan must be active to calculate interest accrued"
        );

        uint256 decimalCompensation = 100000000;

        // calculate seconds as lender
        uint256 secondsOfInterest = decimalCompensation *
            (block.timestamp - loanAuction.timeOfInterestStart);

        // percent of time drawn as Lender
        uint256 percentOfTimeDrawn = secondsOfInterest / loanAuction.timeDrawn;

        // percent of value of amountDrawn earned
        uint256 percentOfAmountDrawn = loanAuction.amountDrawn *
            percentOfTimeDrawn;

        uint256 interestMulPercentOfAmountDrawn;

        // Multiply principle by basis points first
        if (lenderOrProtocol == true) {
            interestMulPercentOfAmountDrawn =
                loanAuction.interestRate *
                percentOfAmountDrawn;
        } else if (lenderOrProtocol == false) {
            interestMulPercentOfAmountDrawn =
                protocolDrawFeePercentage *
                percentOfAmountDrawn;
        }

        // divide by basis decimals
        uint256 interestDecimals = interestMulPercentOfAmountDrawn / 10000;

        // divide by decimalCompensation
        uint256 finalAmount = interestDecimals / decimalCompensation;

        // return interest amount
        return finalAmount;
    }

    // calculate the fullRepayment of a loan
    function calculateFullRepayment(address nftContractAddress, uint256 nftId)
        public
        view
        returns (uint256)
    {
        LoanAuction memory loanAuction = _loanAuctions[nftContractAddress][
            nftId
        ];

        uint256 lenderInterest = calculateInterestAccrued(
            nftContractAddress,
            nftId,
            true
        );

        return
            loanAuction.amountDrawn +
            loanAuction.historicLenderInterest +
            lenderInterest;
    }

    // Returns fullRefinance cost at current timestamp
    function calculateFullRefinanceByLender(
        address nftContractAddress,
        uint256 nftId
    ) public view returns (uint256) {
        LoanAuction memory loanAuction = _loanAuctions[nftContractAddress][
            nftId
        ];

        uint256 lenderInterest = calculateInterestAccrued(
            nftContractAddress,
            nftId,
            true
        );

        // calculate and return refinanceAmount
        return
            loanAuction.amountDrawn +
            lenderInterest +
            loanAuction.historicLenderInterest +
            (loanAuction.amountDrawn * refinancePremiumLenderPercentage) +
            (loanAuction.amountDrawn * refinancePremiumProtocolPercentage);
    }

    // ---------- Fee Update Functions ---------- //

    function updateLoanDrawFee(uint256 newFeeAmount) external onlyOwner {
        protocolDrawFeePercentage = newFeeAmount / 10000;
    }

    function updateRefinancePremiumLenderPercentage(
        uint256 newPremiumLenderPercentage
    ) external onlyOwner {
        refinancePremiumLenderPercentage = newPremiumLenderPercentage / 100000;
    }

    function updateRefinancePremiumProtocolPercentage(
        uint256 newPremiumProtocolPercentage
    ) external onlyOwner {
        refinancePremiumProtocolPercentage =
            newPremiumProtocolPercentage /
            1000;
    }
}
