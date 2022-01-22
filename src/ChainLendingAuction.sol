pragma solidity ^0.8.2;
//SPDX-License-Identifier: MIT

import "./LiquidityProviders.sol";
import "./interfaces/compound/ICEther.sol";
import "./interfaces/IChainLendingAuction.sol";
import "./interfaces/compound/ICERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

contract ChainLendingAuction is
    IChainLendingAuction,
    LiquidityProviders,
    EIP712
{
    // Solidity 0.8.x provides safe math, but uses an invalid opcode error which consumes all gas. SafeMath uses revert which returns all gas.
    using SafeMath for uint256;
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
    uint256 public loanDrawFeeProtocolPercentage = SafeMath.div(1, 10000);

    // premium paid to current lender by new lender for buying out the loan
    uint256 public buyOutPremiumLenderPercentage = SafeMath.div(9, 100000);

    // premium paid to protocol by new lender for buying out the loan
    uint256 public buyOutPremiumProtocolPercentage = SafeMath.div(1, 100000);

    // ---------- FUNCTIONS -------------- //

    constructor() EIP712("NiftyApes", "0.0.1") {}

    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory auction)
    {
        auction = _loanAuctions[nftContractAddress][nftId];
    }

    // ideally this hash can be generated on the frontend, stored in the backend, and provided to functions to reduce computation
    // given the offer details, generate a hash and try to kind of follow the eip-191 standard
    function getOfferHash(Offer memory offer)
        public
        view
        returns (bytes32 offerhash)
    {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
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

    // signature Offer functions

    function getSignatureStatus(bytes memory signature)
        external
        view
        returns (bool status)
    {
        status = _cancelledOrFinalized[signature];
    }

    //ecrecover the signer from hash and the signature
    function getOfferSigner(
        bytes32 offerHash, //hash of offer
        bytes memory signature //proof the actor signed the offer
    ) public pure returns (address signer) {
        return offerHash.toEthSignedMessageHash().recover(signature);
    }

    function getOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external view returns (Offer memory offer) {
        Offer storage offer;
        OfferBook storage offerBook;

        if (floorTerm == true) {
            offerBook = _floorOfferBooks[nftContractAddress];
            return offerBook.offers[offerHash];
        } else if (floorTerm == false) {
            offerBook = _nftOfferBooks[nftContractAddress][nftId];
            return offerBook.offers[offerHash];
        }
    }

    function getOfferAtIndex(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm,
        uint256 index
    ) external view returns (bytes32) {
        Offer memory offer;
        OfferBook storage offerBook;

        if (floorTerm == true) {
            offerBook = _floorOfferBooks[nftContractAddress];
            return offerBook.keys[index];
        } else if (floorTerm == false) {
            offerBook = _nftOfferBooks[nftContractAddress][nftId];
            return offerBook.keys[index];
        }
    }

    function size(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm
    ) external view returns (uint256) {
        Offer memory offer;
        OfferBook storage offerBook;

        if (floorTerm == true) {
            offerBook = _floorOfferBooks[nftContractAddress];
            return offerBook.keys.length;
        } else if (floorTerm == false) {
            offerBook = _nftOfferBooks[nftContractAddress][nftId];
            return offerBook.keys.length;
        }
    }

    function createFloorOffer(address nftContractAddress, Offer memory offer)
        external
    {
        Offer memory offer;
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
            offer.floorTerm
        );
    }

    function createNftOffer(
        address nftContractAddress,
        uint256 nftId,
        Offer memory offer
    ) external {
        Offer memory offer;
        OfferBook storage offerBook = _nftOfferBooks[nftContractAddress][nftId];

        offer.creator = msg.sender;

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
            offer.floorTerm
        );
    }

    function removeFloorOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external {
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
    }

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
    }

    // executeLoanByBid allows a borrower to submit a signed offer from a lender and execute a loan using their owned NFT
    // this external function handles all checks for executeLoanByBid
    function sigExecuteLoanByBid(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId // nftId should match offer.nftId if floorTerm false, nftId should not match if floorTerm true. Need to provide as function parameter to pass nftId with floor terms.
    ) external payable whenNotPaused {
        // require signature has not been cancelled/bid withdrawn
        require(
            _cancelledOrFinalized[signature] == false,
            "Cannot execute bid or ask. Signature has been cancelled or previously finalized."
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

        // ideally calculated, stored, and provided as parameter to save computation
        // generate hash of offer parameters
        bytes32 offerHash = getOfferHash(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // we know the signer must be the lender because msg.sender must be the nftOwner/borrower
        address lender = getOfferSigner(offerHash, signature);

        // // if floorTerm is false
        if (offer.floorTerm == false) {
            // require nftId == sigNftId
            require(
                nftId == offer.nftId,
                "Function submitted nftId must match the signed offer nftId"
            );

            // execute state changes for executeLoanByBid
            _executeLoanByBidInternal(offer, nftId, lender, nftOwner);
        }

        // if floorTerm is true
        if (offer.floorTerm == true) {
            // execute state changes for executeLoanByBid
            _executeLoanByBidInternal(offer, nftId, lender, nftOwner);
        }

        // finalize signature
        _cancelledOrFinalized[signature] == true;

        emit BidAskFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    function chainExecuteLoanByFloorBid(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable whenNotPaused {
        // instantiate Offer Struct
        Offer storage offer = _floorOfferBooks[nftContractAddress].offers[
            offerHash
        ];
        require(offer.floorTerm == true, "Offer must be a floor term");
        _chainExecuteLoanByBidInternal(offer, nftId);
    }

    function chainExecuteLoanByNftBid(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable whenNotPaused {
        // instantiate Offer Struct
        Offer storage offer = _nftOfferBooks[nftContractAddress][nftId].offers[offerHash];
            require(
                offer.floorTerm == false,
                "Offer must be an individual offer"
            );
            require(
                nftId == offer.nftId,
                "Function submitted nftId must match the signed offer nftId"
            );
        _chainExecuteLoanByBidInternal(offer, nftId);
    }

    // executeLoanByBid allows a borrower to submit a signed offer from a lender and execute a loan using their owned NFT
    // this external function handles all checks for executeLoanByBid
    function _chainExecuteLoanByBidInternal(
        Offer storage offer,
        uint256 nftId
    ) internal {
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

        // execute state changes for executeLoanByBid
        _executeLoanByBidInternal(offer, nftId, offer.creator, nftOwner);
    }

    // this internal function _executeLoanByBidInternal handles the state changes for executeLoanByBid
    function _executeLoanByBidInternal(
        Offer memory offer,
        uint256 nftId,
        address lender,
        address nftOwner
    ) internal {
        // instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[
            offer.nftContractAddress
        ][nftId];

        address cAsset = assetToCAsset[offer.asset];

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
        loanAuction.bestBidTime = block.timestamp;
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

    function sigExecuteLoanByAsk(Offer calldata offer, bytes calldata signature)
        external
        payable
    {
        // require signature has not been cancelled/bid withdrawn
        require(
            _cancelledOrFinalized[signature] == false,
            "Cannot execute bid or ask. Signature has been cancelled or previously finalized."
        );

        // ideally calculated, stored, and provided as parameter to save computation
        bytes32 offerHash = getOfferHash(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // We assume the signer is the borrower and check in the following require statment
        address borrower = getOfferSigner(offerHash, signature);

        // get nft owner
        address nftOwner = IERC721(offer.nftContractAddress).ownerOf(
            offer.nftId
        );

        // require signer/borrower is the nftOwner. This ensures the signer/borrower is the owner of the NFT
        require(
            nftOwner == borrower,
            "Borrower must be the owner of nftId to executeLoanByAsk"
        );

        // execute state changes for executeLoanByAsk
        _executeLoanByAskInternal(offer, msg.sender, nftOwner);

        // this should be done only after all checks if possible
        // finalize signature
        _cancelledOrFinalized[signature] == true;

        emit BidAskFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    // executeLoanByAsk allows a lender to submit a signed offer from a borrower and execute a loan against the borrower's NFT
    // this external function handles all checks for executeLoanByAsk
    function chainExecuteLoanByAsk(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) public payable {
        // instantiate LoanAuction Struct
        Offer storage offer = _nftOfferBooks[nftContractAddress][nftId].offers[
            offerHash
        ];

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
            assetToCAsset[offer.asset] != address(0),
            "Asset not whitelisted on NiftyApes"
        );

        // get nft owner
        address nftOwner = IERC721(offer.nftContractAddress).ownerOf(
            offer.nftId
        );

        // require signer/borrower is the nftOwner. This ensures the signer/borrower is the owner of the NFT
        require(
            nftOwner == offer.creator,
            "Borrower must be the owner of nftId to executeLoanByAsk"
        );

        // execute state changes for executeLoanByAsk
        _executeLoanByAskInternal(offer, msg.sender, nftOwner);
    }

    // this internal function handles all state changes for executeLoanByAsk
    function _executeLoanByAskInternal(
        Offer memory offer,
        address lender,
        address nftOwner
    ) internal {
        // instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[
            offer.nftContractAddress
        ][offer.nftId];

        address cAsset = assetToCAsset[offer.asset];

        // require loan is not active
        require(
            loanAuction.loanExecutedTime == 0,
            "Loan is already active. Please use refinanceByLender()"
        );

        // check if lender has sufficient available balance and update utilizedBalance
        _checkAndUpdateLenderUtilizedBalanceInternal(
            cAsset,
            offer.amount,
            lender
        );

        // update LoanAuction struct
        loanAuction.nftOwner = nftOwner;
        loanAuction.lender = lender;
        loanAuction.asset = offer.asset;
        loanAuction.amount = offer.amount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.duration = offer.duration;
        loanAuction.bestBidTime = block.timestamp;
        loanAuction.loanExecutedTime = block.timestamp;
        loanAuction.timeDrawn = offer.duration;
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;

        // calculate protocol draw fee and subtract from amount
        // this leaves the protocol fee invested in Compound in this contract address' balance
        uint256 drawAmountMinusFee = offer.amount -
            (offer.amount * loanDrawFeeProtocolPercentage);

        // *------- value and asset transfers -------* //

        // transferFrom NFT from nftOwner to contract
        IERC721(offer.nftContractAddress).transferFrom(
            nftOwner,
            address(this),
            offer.nftId
        );

        // Process as ETH
        if (
            offer.asset == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferEthInternal(cAsset, drawAmountMinusFee, nftOwner);
        }
        // Process as ERC20
        else {
            _redeemAndTransferErc20Internal(
                offer.asset,
                cAsset,
                drawAmountMinusFee,
                nftOwner
            );
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
        cToken.redeemUnderlying(amount);

        // Send Eth to borrower
        (bool success, ) = (nftOwner).call{value: amount}("");
        require(success, "Send eth to depositor failed");
    }

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

    // this
    function sigRefinanceByBorrower(Offer memory offer, bytes memory signature)
        external
        payable
        whenNotPaused
    {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[
            offer.nftContractAddress
        ][offer.nftId];

        address cAsset = assetToCAsset[loanAuction.asset];

        // Require that loan does not have fixedTerms
        require(
            loanAuction.fixedTerms != true,
            "Loan has fixedTerms cannot buyOutBestBid."
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

        // get nft owner
        address nftOwner = IERC721(offer.nftContractAddress).ownerOf(
            offer.nftId
        );

        // require msg.sender is the nftOwner/borrower
        require(
            nftOwner == msg.sender,
            "Msg.sender must be the owner of nftId to refinanceByBorrower"
        );

        // ideally calculated, stored, and provided as parameter to save computation
        bytes32 offerHash = getOfferHash(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // We assume the signer is the lender because msg.sender must the the nftOwner
        address prospectiveLender = getOfferSigner(offerHash, signature);

        // calculate the interest earned by current lender
        uint256 lenderInterest = calculateInterestAccruedBylender(
            offer.nftContractAddress,
            offer.nftId
        );

        // calculate interest earned
        uint256 interestOwedToLender = lenderInterest +
            loanAuction.historicInterest;

        uint256 fullRepayment = loanAuction.amountDrawn + interestOwedToLender;

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

        // update LoanAuction struct
        loanAuction.lender = prospectiveLender;
        loanAuction.amount = offer.amount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.duration = offer.duration;
        loanAuction.bestBidTime = block.timestamp;
        loanAuction.historicInterest = 0;

        // pull down funds from new lender

        // stack too deep for these event variables, need to refactor
        // emit LoanBuyOut(
        //     lender,
        //     nftOwner,
        //     offer.nftContractAddress,
        //     offer.nftId,
        //     offer.asset,
        //     offer.amount,
        //     offer.interestRate,
        //     offer.duration
        // );

        // emit BidAskFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    function chainRefinanceByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable whenNotPaused {
        Offer storage offer = _nftOfferBooks[nftContractAddress][nftId].offers[
            offerHash
        ];

        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = _loanAuctions[
            offer.nftContractAddress
        ][offer.nftId];

        address cAsset = assetToCAsset[loanAuction.asset];

        // Require that loan does not have fixedTerms
        require(
            loanAuction.fixedTerms != true,
            "Loan has fixedTerms cannot buyOutBestBid."
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

        // get nft owner
        address nftOwner = IERC721(offer.nftContractAddress).ownerOf(
            offer.nftId
        );

        // require msg.sender is the nftOwner/borrower
        require(
            nftOwner == msg.sender,
            "Msg.sender must be the owner of nftId to refinanceByBorrower"
        );

        // calculate the interest earned by current lender
        uint256 lenderInterest = calculateInterestAccruedBylender(
            offer.nftContractAddress,
            offer.nftId
        );

        // calculate interest earned
        uint256 interestOwedToLender = lenderInterest +
            loanAuction.historicInterest;

        uint256 fullRepayment = loanAuction.amountDrawn + interestOwedToLender;

        address prospectiveLender = offer.creator;

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

        // update LoanAuction struct
        loanAuction.lender = prospectiveLender;
        loanAuction.amount = offer.amount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.duration = offer.duration;
        loanAuction.bestBidTime = block.timestamp;
        loanAuction.historicInterest = 0;

        // pull down funds from new lender

        // stack too deep for these event variables, need to refactor
        // emit LoanBuyOut(
        //     lender,
        //     nftOwner,
        //     offer.nftContractAddress,
        //     offer.nftId,
        //     offer.asset,
        //     offer.amount,
        //     offer.interestRate,
        //     offer.duration
        // );

        // emit BidAskFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

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
            "Loan has fixedTerms cannot buyOutBestBid."
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
                "Cannot buyOutBestBid. Offer duration must be at least 24 hours greater than current loan. "
            );
        }

        // calculate the interest earned by current lender
        uint256 lenderInterest = calculateInterestAccruedBylender(
            offer.nftContractAddress,
            offer.nftId
        );

        // calculate interest earned
        uint256 interestAndPremiumOwedToLender = lenderInterest +
            loanAuction.historicInterest +
            (loanAuction.amountDrawn * buyOutPremiumLenderPercentage);

        // calculate protocolPremiumFee
        uint256 protocolPremiumFee = loanAuction.amountDrawn *
            buyOutPremiumProtocolPercentage;

        // calculate fullBidBuyOutAmount
        uint256 fullBuyOutAmount = interestAndPremiumOwedToLender +
            protocolPremiumFee +
            loanAuction.amountDrawn;
        // If refinancing is not done by current lender they must buy out the loan and pay fees
        if (loanAuction.lender != msg.sender) {
            // require prospective lender has sufficient available balance to refinance loan
            require(
                (cAssetBalances[cAsset][msg.sender] -
                    utilizedCAssetBalances[cAsset][msg.sender]) >=
                    fullBuyOutAmount,
                "Prospective lender does not have sufficient balance to refinance loan"
            );

            // processes cEth and ICERC20 transactions
            _transferICERC20BalancesInternal(
                cAsset,
                loanAuction.lender,
                msg.sender,
                protocolPremiumFee,
                interestAndPremiumOwedToLender,
                loanAuction.amountDrawn
            );

            // update LoanAuction lender
            loanAuction.lender = msg.sender;

            // If current lender is refinancing the loan they do not need to pay any fees or buy themselves out.
        } else if (loanAuction.lender == msg.sender) {
            require(
                (cAssetBalances[cAsset][msg.sender] -
                    utilizedCAssetBalances[cAsset][msg.sender]) >=
                    offer.amount - loanAuction.amountDrawn,
                "Lender does not have sufficient balance to refinance loan"
            );
        }

        // save temporary current historicInterest
        uint256 currentHistoricInterest = loanAuction.historicInterest;

        // update LoanAuction struct
        loanAuction.amount = offer.amount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.duration = offer.duration;
        loanAuction.bestBidTime = block.timestamp;
        loanAuction.historicInterest = currentHistoricInterest + lenderInterest;

        emit LoanBuyOut(
            msg.sender,
            loanAuction.nftOwner,
            offer.nftContractAddress,
            offer.nftId,
            offer.asset,
            offer.amount,
            offer.interestRate,
            offer.duration
        );
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

        // require from has a sufficient total balance to buy out loan

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

    // Cancel a signature based bid or ask on chain
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

        // Require that from is signer of the signature
        require(
            signer == msg.sender,
            "Msg.sender is not the signer of the submitted signature"
        );

        // cancel signature
        _cancelledOrFinalized[signature] = true;

        emit BidAskCancelled(offer.nftContractAddress, offer.nftId, signature);
    }

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

        // Require that loan has not expired
        require(
            block.timestamp <
                loanAuction.loanExecutedTime + loanAuction.timeDrawn,
            "Cannot seize asset before the end of the loan"
        );

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

        // set timeDrawn
        loanAuction.timeDrawn += drawTime;

        emit TimeDrawn(
            nftContractAddress,
            nftId,
            drawTime,
            loanAuction.timeDrawn
        );
    }

    function drawAmount(
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

        // Require amountDrawn is less than the bestBidAmount
        require(
            loanAuction.amountDrawn < loanAuction.amount,
            "Draw down amount not available"
        );

        // Require that drawAmount does not exceed amount
        require(
            (drawAmount + loanAuction.amountDrawn) <= loanAuction.amount,
            "Total amount withdrawn must not exceed best bid loan amount"
        );

        _checkAndUpdateLenderUtilizedBalanceInternal(
            cAsset,
            drawAmount,
            loanAuction.lender
        );

        // set amountDrawn
        loanAuction.amountDrawn += drawAmount;

        // calculate fee and subtract from drawAmount
        uint256 drawAmountMinusFee = drawAmount -
            (drawAmount * loanDrawFeeProtocolPercentage);

        // if asset is not 0x0 process as Erc20
        if (
            loanAuction.asset !=
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferErc20Internal(
                loanAuction.asset,
                cAsset,
                drawAmountMinusFee,
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
                drawAmountMinusFee,
                loanAuction.nftOwner
            );
        }

        emit AmountDrawn(
            nftContractAddress,
            nftId,
            drawAmount,
            drawAmountMinusFee,
            loanAuction.amountDrawn
        );
    }

    // enables borrowers to repay their full loan to a lender and regain full ownership of their NFT
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

        // get nft owner
        address nftOwner = loanAuction.nftOwner;

        // Require msg.sender is the borrower
        require(
            msg.sender == loanAuction.nftOwner,
            "Msg.sender is not the NFT owner"
        );

        // calculate the amount of interest accrued by the lender
        uint256 lenderInterest = calculateInterestAccruedBylender(
            nftContractAddress,
            nftId
        );

        // calculate total interest value owed
        uint256 interestOwedToLender = lenderInterest +
            loanAuction.historicInterest;

        uint256 protocolDrawFee = loanAuction.amountDrawn *
            loanDrawFeeProtocolPercentage;

        // get required repayment
        uint256 fullRepayment = interestOwedToLender +
            protocolDrawFee +
            loanAuction.amountDrawn;

        // if asset is not 0x0 process as Erc20
        if (
            loanAuction.asset !=
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // protocolPremiumFee is taken here. Full amount is minted to this contract address' balance in Compound and amount owed to lender is updated in their balance. The delta is the protocol premium fee.
            _payErc20AndUpdateBalancesInternal(
                loanAuction.asset,
                cAsset,
                loanAuction.lender,
                msg.sender,
                fullRepayment,
                interestOwedToLender,
                loanAuction.amountDrawn
            );
        }
        // else process as ETH
        else if (
            loanAuction.asset ==
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // check that transaction covers the full value of the loan
            require(
                msg.value >= fullRepayment,
                "Must repay full amount of loan drawn plus interest and fee. Account for additional time for interest."
            );
            // protocolPremiumFee is taken here. Full amount is minted to this contract address' balance in Compound and amount owed to lender is updated in their balance. The delta is the protocol premium fee.
            _payEthAndUpdateBalancesInternal(
                cAsset,
                loanAuction.lender,
                msg.value,
                msg.value,
                interestOwedToLender,
                loanAuction.amountDrawn
            );
        }

        // reset loanAuction
        loanAuction.nftOwner = address(0);
        loanAuction.lender = address(0);
        loanAuction.asset = address(0);
        loanAuction.amount = 0;
        loanAuction.interestRate = 0;
        loanAuction.duration = 0;
        loanAuction.bestBidTime = 0;
        loanAuction.loanExecutedTime = 0;
        loanAuction.historicInterest = 0;
        loanAuction.amountDrawn = 0;
        loanAuction.timeDrawn = 0;
        loanAuction.fixedTerms = false;

        // transferFrom NFT from contract to nftOwner
        IERC721(nftContractAddress).transferFrom(
            address(this),
            nftOwner,
            nftId
        );

        emit LoanRepaidInFull(nftContractAddress, nftId);

        return 0;
    }

    // enables borrowers to make a partial payment on their loan
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

        // calculate interestAmount
        uint256 interestAmount = partialAmount *
            (loanAuction.interestRate * 100);

        uint256 protocolDrawFee = partialAmount * loanDrawFeeProtocolPercentage;

        // calculate paymentAmount
        uint256 paymentAmount = partialAmount -
            interestAmount -
            protocolDrawFee;

        // if asset is not 0x0 process as Erc20
        if (
            loanAuction.asset !=
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            _payErc20AndUpdateBalancesInternal(
                loanAuction.asset,
                cAsset,
                loanAuction.lender,
                msg.sender,
                partialAmount,
                interestAmount,
                paymentAmount
            );
        }
        // else process as ETH
        else if (
            loanAuction.asset ==
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            // check that transaction covers the full value of the loan
            require(
                msg.value < loanAuction.amountDrawn,
                "Msg.value must be less than amountDrawn"
            );

            _payEthAndUpdateBalancesInternal(
                cAsset,
                loanAuction.lender,
                msg.value,
                msg.value,
                interestAmount,
                paymentAmount
            );
        }

        // update amountDrawn
        loanAuction.amountDrawn -= paymentAmount;

        emit PartialRepayment(
            nftContractAddress,
            nftId,
            loanAuction.asset,
            partialAmount
        );
    }

    // this internal functions handles transfer of erc20 tokens and updating lender balances for buyOutLoan, repayRemainingLoan, and partialRepayment functions
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

    // this internal functions handles transfer of Eth and updating lender balances for buyOutLoan, repayRemainingLoan, and partialRepayment functions
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
        utilizedCAssetBalances[cAsset][to] -= paymentAmount;

        // update the to's total balance
        cAssetBalances[cAsset][to] += (interestAndPremiumTokens + mintDelta);

        return 0;
    }

    // allows anyone to seize an asset of a past due loan on behalf on the lender
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
        loanAuction.bestBidTime = 0;
        loanAuction.loanExecutedTime = 0;
        loanAuction.historicInterest = 0;
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

    // returns the interest value earned by lender on active amountDrawn
    function calculateInterestAccruedBylender(
        address nftContractAddress,
        uint256 nftId
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
        uint256 secondsAslender = SafeMath.mul(
            decimalCompensation,
            (block.timestamp - loanAuction.bestBidTime)
        );

        // percent of time drawn as Lender
        uint256 percentOfTimeDrawnAsLender = SafeMath.div(
            secondsAslender,
            loanAuction.timeDrawn
        );

        // percent of value of amountDrawn earned
        uint256 percentOfAmountDrawn = SafeMath.mul(
            loanAuction.amountDrawn,
            percentOfTimeDrawnAsLender
        );

        // Multiply principle by basis points first
        uint256 interestMulPercentOfAmountDrawn = SafeMath.mul(
            loanAuction.interestRate,
            percentOfAmountDrawn
        );

        // divide by basis decimals
        uint256 interestDecimals = SafeMath.div(
            interestMulPercentOfAmountDrawn,
            10000
        );

        // divide by decimalCompensation
        uint256 finalAmount = SafeMath.div(interestDecimals, 100000000);

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

        uint256 lenderInterest = calculateInterestAccruedBylender(
            nftContractAddress,
            nftId
        );

        return
            loanAuction.amountDrawn +
            loanAuction.historicInterest +
            lenderInterest;
    }

    // Returns fullBidBuyOut cost at current timestamp
    function calculateFullBidBuyOut(address nftContractAddress, uint256 nftId)
        public
        view
        returns (uint256)
    {
        LoanAuction memory loanAuction = _loanAuctions[nftContractAddress][
            nftId
        ];

        uint256 lenderInterest = calculateInterestAccruedBylender(
            nftContractAddress,
            nftId
        );

        // calculate and return buyOutAmount
        return
            loanAuction.amountDrawn +
            lenderInterest +
            loanAuction.historicInterest +
            (loanAuction.amountDrawn * buyOutPremiumLenderPercentage) +
            (loanAuction.amountDrawn * buyOutPremiumProtocolPercentage);
    }

    function updateLoanDrawFee(uint256 newFeeAmount) external onlyOwner {
        loanDrawFeeProtocolPercentage = SafeMath.div(newFeeAmount, 10000);
    }

    function updateBuyOutPremiumLenderPercentage(
        uint256 newPremiumLenderPercentage
    ) external onlyOwner {
        buyOutPremiumLenderPercentage = SafeMath.div(
            newPremiumLenderPercentage,
            100000
        );
    }

    function updateBuyOutPremiumProtocolPercentage(
        uint256 newPremiumProtocolPercentage
    ) external onlyOwner {
        buyOutPremiumProtocolPercentage = SafeMath.div(
            newPremiumProtocolPercentage,
            1000
        );
    }
}
