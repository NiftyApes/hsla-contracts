pragma solidity ^0.8.2;
//SPDX-License-Identifier: MIT

import "./LiquidityProviders.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

contract SignatureLendingAuction is LiquidityProviders, EIP712 {
    // Solidity 0.8.x provides safe math, but uses an invalid opcode error which comsumes all gas. SafeMath uses revert which returns all gas.
    using SafeMath for uint256;
    using ECDSA for bytes32;

    // ---------- STRUCTS --------------- //

    struct LoanAuction {
        // NFT owner
        address nftOwner;
        // Current lender
        address lender;
        // loan asset
        address asset; // 0x0 in active loan denotes ETH
        // loan amount
        uint256 loanAmount;
        // loan interest rate
        uint256 interestRate;
        // loan duration of loan in number of seconds
        uint256 loanDuration;
        // timestamp of bestBid
        uint256 bestBidTime;
        // timestamp of loan execution
        uint256 loanExecutedTime;
        // cumulative interest of varying rates paid by new lenders to buy out the loan auction
        uint256 historicInterest;
        // amount withdrawn by the nftOwner. This is the amount they will pay interest on, with this value as minimum
        uint256 amountDrawn;
        // time withdrawn by the nftOwner. This is the time they will pay interest on, with this value as minimum
        uint256 timeDrawn;
        // boolean of whether fixedTerms has been accepted by a borrower
        // if fixedTerms == true could mint an NFT that represents that loan to enable packaging and reselling.
        bool fixedTerms;
    }

    struct Offer {
        // offer NFT contract address
        address nftContractAddress;
        // offer NFT ID
        uint256 nftId; // 0 if floorTerm is true
        // offer asset type
        address asset;
        // offer loan amount
        uint256 loanAmount;
        // offer interest rate
        uint256 interestRate;
        // offer loan duration
        uint256 duration;
        // offer expiration
        uint256 expiration;
        // is loan offer fixed terms or open for perpetual auction
        bool fixedTerms;
        // is offer for single NFT or for every NFT in a collection
        bool floorTerm;
    }

    // ---------- STATE VARIABLES --------------- //

    // Mapping of nftId to nftContractAddress to LoanAuction struct
    mapping(address => mapping(uint256 => LoanAuction)) public loanAuctions;

    // Cancelled / finalized orders, by signature
    mapping(bytes => bool) public cancelledOrFinalized;

    // fee paid to protocol by borrower for drawing down loan
    uint256 loanDrawFeeProtocolPercentage = SafeMath.div(1, 100);

    // premium paid to current lender by new lender for buying out the loan
    uint256 buyOutPremiumLenderPrecentage = SafeMath.div(9, 1000);

    // premium paid to protocol by new lender for buying out the loan
    uint256 buyOutPremiumProtocolPrecentage = SafeMath.div(1, 1000);

    // ---------- EVENTS --------------- //

    // New Best Bid event
    event NewBestBid(
        address _lender,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        uint256 _loanAmount,
        uint256 _interestRate,
        uint256 _loanDuration
    );

    event BestBidWithdrawn(
        address indexed nftContractAddress,
        uint256 indexed nftId
    );

    event NewAsk(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        uint256 _askLoanAmount,
        uint256 _askInterestRate,
        uint256 _askLoanDuration
    );

    event AskWithdrawn(
        address indexed nftContractAddress,
        uint256 indexed nftId
    );

    event LoanExecuted(
        address _lender,
        address nftOwner,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        uint256 _loanAmount,
        uint256 _interestRate,
        uint256 _loanDuration
    );

    event LoanDrawn(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        uint256 _drawAmount,
        uint256 _drawAmountMinusFee,
        uint256 _totalDrawn
    );

    event LoanRepaidInFull(
        address indexed nftContractAddress,
        uint256 indexed nftId
    );

    event AssetSeized(
        address indexed nftContractAddress,
        uint256 indexed nftId
    );

    // cancellation sig event
    event BidAskCancelled(
        address indexed nftContractAddress,
        uint256 indexed nftId
    );

    // finalize sig event
    event BidAskFinalized(
        address indexed nftContractAddress,
        uint256 indexed nftId
    );

    // ---------- MODIFIERS --------------- //

    modifier isNFTOwner(address nftContractAddress, uint256 nftId) {
        _;
    }

    // ---------- FUNCTIONS -------------- //

    constructor() EIP712("NiftyApes", "0.0.1") {}

    // ideally this hash can be generated on the frontend, stored in the backend, and provided to functions to reduce computation
    // given the offer details, generate a hash and try to kind of follow the eip-191 standard
    function getOfferHash(Offer memory offer)
        public
        view
        returns (bytes32 offerhash)
    {
        // originally 'byte' values, but solidity compiler was throwing error. If cant match signature investigate this.
        // abi.encodePacked(
        // byte(0x19),
        // byte(0),

        // return
        //     keccak256(
        //         abi.encodePacked(
        //             bytes1(0x19),
        //             bytes1(0),
        //             address(this),
        //             offer.nftContractAddress,
        //             offer.nftId,
        //             offer.asset,
        //             offer.loanAmount,
        //             offer.interestRate,
        //             offer.duration,
        //             offer.expiration,
        //             offer.fixedTerms,
        //             offer.floorTerm
        //         )
        //     );

        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        offer.nftContractAddress,
                        offer.nftId,
                        offer.asset,
                        offer.loanAmount,
                        offer.interestRate,
                        offer.duration,
                        offer.expiration,
                        offer.fixedTerms,
                        offer.floorTerm
                    )
                )
            );
    }

    //ecrecover the signer from hash and the signature
    function getOfferSigner(
        bytes32 offerHash, //hash of offer
        bytes memory signature //proof the actor signed the offer
    ) public pure returns (address) {
        return offerHash.toEthSignedMessageHash().recover(signature);
    }

    // executeLoanByBid allows a borrower to submit a signed offer from a lender and execute a loan using their owned NFT
    // this external function handles all checks for executeLoanByBid
    function executeLoanByBid(
        Offer memory offer,
        // bytes offerHash,
        bytes memory signature,
        uint256 nftId // nftId should match offer.nftId if floorTerm false, nftId should not match if floorTerm true. Need to provide as function parameter to pass nftId with floor terms.
    ) external payable whenNotPaused {
        console.log("inside");
        // require signature has not been cancelled/bid withdrawn
        require(
            cancelledOrFinalized[signature] == false,
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

        console.log("here 1");

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
            _executeLoanByBidInternal(
                offer,
                nftId,
                lender,
                nftOwner,
                signature
            );
        }

        // if floorTerm is true
        if (offer.floorTerm == true) {
            // execute state changes for executeLoanByBid
            _executeLoanByBidInternal(
                offer,
                nftId,
                lender,
                nftOwner,
                signature
            );
        }

        
    }

    // this internal function _executeLoanByBidInternal handles the state changes for executeLoanByBid
    function _executeLoanByBidInternal(
        Offer memory offer,
        uint256 nftId,
        address lender,
        address nftOwner,
        bytes memory signature
    ) internal {
        console.log("hello from the top");
        // instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[
            offer.nftContractAddress
        ][nftId];

        address cAsset = assetToCAsset[offer.asset];

        // if loan is not active execute intial loan
        if (loanAuction.loanExecutedTime == 0) {
            // finalize signature
            cancelledOrFinalized[signature] == true;

            // check if lender has sufficient available balance and update utilizedBalance
            _checkAndUpdateLenderUtilizedBalanceInternal(
                cAsset,
                offer.loanAmount,
                lender
            );

            // update loanAuction struct
            loanAuction.nftOwner = nftOwner;
            loanAuction.lender = lender;
            loanAuction.asset = offer.asset;
            loanAuction.loanAmount = offer.loanAmount;
            loanAuction.interestRate = offer.interestRate;
            loanAuction.loanDuration = offer.duration;
            loanAuction.bestBidTime = block.timestamp;
            loanAuction.loanExecutedTime = block.timestamp;
            loanAuction.timeDrawn = offer.duration;
            loanAuction.amountDrawn = offer.loanAmount;
            loanAuction.fixedTerms = offer.fixedTerms;

            // calculate protocol draw fee and subtract from loanAmount
            // this leaves the protocol fee invested in Compound in this contract address' balance
            uint256 drawAmountMinusFee = offer.loanAmount -
                (offer.loanAmount * loanDrawFeeProtocolPercentage);

            // *------- value and asset transfers -------* //

            // transferFrom NFT from nftOwner to contract
            IERC721(offer.nftContractAddress).transferFrom(
                nftOwner,
                address(this),
                nftId
            );

            // if asset is not 0x0 process as Erc20
            if (offer.asset != 0x0000000000000000000000000000000000000000) {
                // redeem cTokens and transfer underlying to borrower
                _redeemAndTransferErc20Internal(
                    offer.asset,
                    cAsset,
                    drawAmountMinusFee,
                    nftOwner
                );
            }
            // else process as ETH
            else if (
                offer.asset == 0x0000000000000000000000000000000000000000
            ) {
                // redeem cTokens and transfer underlying to borrower
                _redeemAndTransferEthInternal(
                    cAsset,
                    drawAmountMinusFee,
                    nftOwner
                );
            }
        }
        // else if loan is active, borrower pays off loan and executes new loan
        else if (loanAuction.loanExecutedTime != 0) {
            // may be better to refactor and create specific bestBidBuyOutbyborrower function
            // buyOutBestBidByBorrower(offer);
            // pay off current loan
            repayRemainingLoan(offer.nftContractAddress, nftId);
            // execute new loan
            _executeLoanByBidInternal(
                offer,
                nftId,
                lender,
                nftOwner,
                signature
            );
        }

        console.log("hello from the bottom");
    }

    // executeLoanByAsk allows a lender to submit a signed offer from a borrower and execute a loan against the borrower's NFT
    // this external function handles all checks for executeLoanByAsk
    function executeLoanByAsk(
        Offer memory offer,
        // bytes offerHash,
        bytes memory signature
    ) public payable {
        // require signature has not been cancelled/bid withdrawn
        require(
            cancelledOrFinalized[signature] == false,
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

        // get nft owner
        address nftOwner = IERC721(offer.nftContractAddress).ownerOf(
            offer.nftId
        );

        // ideally calculated, stored, and provided as parameter to save computation
        bytes32 offerHash = getOfferHash(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // We assume the signer is the borrower and check in the following require statment
        address borrower = getOfferSigner(offerHash, signature);

        // require signer/borrower is the nftOwner. This ensures the signer/borrower is the owner of the NFT
        require(
            nftOwner == borrower,
            "Borrower must be the owner of nftId to executeLoanByAsk"
        );

        // execute state changes for executeLoanByAsk
        _executeLoanByAskInternal(offer, msg.sender, nftOwner, signature);
    }

    // this internal function handles all state changes for executeLoanByAsk
    function _executeLoanByAskInternal(
        Offer memory offer,
        address lender,
        address nftOwner,
        bytes memory signature
    ) internal {
        // instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[
            offer.nftContractAddress
        ][offer.nftId];

        address cAsset = assetToCAsset[offer.asset];

        // require loan is not active
        require(
            loanAuction.loanExecutedTime == 0,
            "Loan is already active. Cannot execute new ask."
        );

        // finalize signature
        cancelledOrFinalized[signature] == true;

        // check if lender has sufficient available balance and update utilizedBalance
        _checkAndUpdateLenderUtilizedBalanceInternal(
            cAsset,
            offer.loanAmount,
            lender
        );

        // update LoanAuction struct
        loanAuction.nftOwner = nftOwner;
        loanAuction.lender = lender;
        loanAuction.asset = offer.asset;
        loanAuction.loanAmount = offer.loanAmount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.loanDuration = offer.duration;
        loanAuction.bestBidTime = block.timestamp;
        loanAuction.loanExecutedTime = block.timestamp;
        loanAuction.timeDrawn = offer.duration;
        loanAuction.amountDrawn = offer.loanAmount;
        loanAuction.fixedTerms = offer.fixedTerms;

        // calculate protocol draw fee and subtract from loanAmount
        // this leaves the protocol fee invested in Compound in this contract address' balance
        uint256 drawAmountMinusFee = offer.loanAmount -
            (offer.loanAmount * loanDrawFeeProtocolPercentage);

        // *------- value and asset transfers -------* //

        // transferFrom NFT from nftOwner to contract
        IERC721(offer.nftContractAddress).transferFrom(
            nftOwner,
            address(this),
            offer.nftId
        );

        // if asset is not 0x0 process as Erc20
        if (offer.asset != 0x0000000000000000000000000000000000000000) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferErc20Internal(
                offer.asset,
                cAsset,
                drawAmountMinusFee,
                nftOwner
            );
        }
        // else process as ETH
        else if (offer.asset == 0x0000000000000000000000000000000000000000) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferEthInternal(cAsset, drawAmountMinusFee, nftOwner);
        }
    }

    // this internal functions handles transfer of erc20 tokens for executeLoan functions
    function _redeemAndTransferErc20Internal(
        address asset,
        address cAsset,
        uint256 amount,
        address nftOwner
    ) internal {

        console.log("asset", asset);
        console.log("asset", cAsset);
        console.log("amount", amount);
        console.log("nftOwner", nftOwner);

        // Create a reference to the underlying asset contract, like DAI.
        Erc20 underlying = Erc20(asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(cAsset);

        // redeem underlying from cToken to this contract
        cToken.rede++emUnderlying(amount);

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
        CErc20 cToken = CErc20(cAsset);

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
        CErc20 cToken = CErc20(cAsset);

        // instantiate RedeemLocalVars
        RedeemLocalVars memory vars;

        // set exchangeRate of erc20 to cErc20
        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        // convert amount to cErc20
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
            // calculate lenders available cErc20 balance and require it to be greater than or equal to vars.redeemTokens
            (cErc20Balances[cAsset][lender] -
                utilizedCErc20Balances[cAsset][lender]) >= vars.redeemTokens,
            "Lender does not have a sufficient balance to serve this loan"
        );

        // update the lenders utilized balance
        utilizedCErc20Balances[cAsset][lender] += vars.redeemTokens;

        return 0;
    }

    function buyOutBestBidByBorrower(Offer memory offer, bytes memory signature)
        public
        payable
        whenNotPaused
    {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[
            offer.nftContractAddress
        ][offer.nftId];

        address cAsset = assetToCAsset[offer.asset];

        // Require that loan does not have fixedTerms
        require(
            loanAuction.fixedTerms != true,
            "Loan has fixedTerms cannot buyOutBestBid."
        );

        // Require that loan is active
        require(
            loanAuction.loanExecutedTime != 0,
            "Loan is not active. No funds to withdraw."
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
            "Msg.sender must be the owner of nftId to buyOutBestBidByBorrower"
        );

        // ideally calculated, stored, and provided as parameter to save computation
        bytes32 offerHash = getOfferHash(offer);

        // recover singer and confirm signed offer terms with function submitted offer terms
        // We assume the signer is the lender because msg.sender must the the nftOwner
        address lender = getOfferSigner(offerHash, signature);

        // calculate the interest earned by current lender
        uint256 lenderInterest = calculateInterestAccruedBylender(
            offer.nftContractAddress,
            offer.nftId
        );

        // calculate interest earned
        uint256 interestOwedToLender = lenderInterest +
            loanAuction.historicInterest;

        uint256 fullRepayment = loanAuction.amountDrawn + interestOwedToLender;

        // if asset is not 0x0 process as Erc20
        if (loanAuction.asset != 0x0000000000000000000000000000000000000000) {
            _payErc20AndUpdateBalancesInternal(
                loanAuction.asset,
                cAsset,
                loanAuction.lender,
                fullRepayment,
                interestOwedToLender,
                loanAuction.amountDrawn
            );
        }
        // else process as ETH
        else if (
            loanAuction.asset == 0x0000000000000000000000000000000000000000
        ) {
            // require transaction has enough value to pay out current lender and protocol premium fee
            require(
                msg.value >= fullRepayment,
                "Transaction must contain enough value to pay out currentlender plus premium"
            );

            _payEthAndUpdateBalancesInternal(
                cAsset,
                loanAuction.lender,
                msg.value,
                msg.value,
                interestOwedToLender,
                loanAuction.amountDrawn
            );
        }

        // update LoanAuction struct
        loanAuction.lender = lender;
        loanAuction.loanAmount = offer.loanAmount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.loanDuration = offer.duration;
        loanAuction.bestBidTime = block.timestamp;
        loanAuction.historicInterest = 0;
    }

    function buyOutBestBidByLender(Offer memory offer)
        public
        payable
        whenNotPaused
        nonReentrant
    {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[
            offer.nftContractAddress
        ][offer.nftId];

        address cAsset = assetToCAsset[offer.asset];

        // Require that loan does not have fixedTerms
        require(
            loanAuction.fixedTerms != true,
            "Loan has fixedTerms cannot buyOutBestBid."
        );

        // Require that loan is active
        require(
            loanAuction.loanExecutedTime != 0,
            "Loan is not active. No funds to withdraw."
        );

        // require offer is same asset
        require(
            offer.asset == loanAuction.asset,
            "Offer asset must be the same as the current loan"
        );

        // require that terms are parity + 1
        require(
            // Require bidAmount is greater than previous bid
            (offer.loanAmount > loanAuction.loanAmount &&
                offer.interestRate <= loanAuction.interestRate &&
                offer.duration >= loanAuction.loanDuration) ||
                // OR
                // Require interestRate is lower than previous bid
                (offer.loanAmount >= loanAuction.loanAmount &&
                    offer.interestRate < loanAuction.interestRate &&
                    offer.duration >= loanAuction.loanDuration) ||
                // OR
                // Require loanDuration to be greater than previous bid
                (offer.loanAmount >= loanAuction.loanAmount &&
                    offer.interestRate <= loanAuction.interestRate &&
                    offer.duration > loanAuction.loanDuration),
            "Bid must have better terms than current loan"
        );

        // if duration is the only term updated
        if (
            offer.loanAmount == loanAuction.loanAmount &&
            offer.interestRate == loanAuction.interestRate &&
            offer.duration > loanAuction.loanDuration
        ) {
            // require offer has at least 24 hour additional duration
            require(
                offer.duration >= (loanAuction.loanDuration + 86400),
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
            (loanAuction.amountDrawn * buyOutPremiumLenderPrecentage);

        // calculate fullBidBuyOutAmount
        uint256 fullBidBuyOutAmount = calculateFullBidBuyOut(
            offer.nftContractAddress,
            offer.nftId
        );

        // calculate msgValueMinusProtocolPremiumFee
        uint256 msgValueMinusProtocolPremiumFee = msg.value -
            (loanAuction.amountDrawn * buyOutPremiumProtocolPrecentage);

        // if asset is not 0x0 process as Erc20
        if (loanAuction.asset != 0x0000000000000000000000000000000000000000) {
            _payErc20AndUpdateBalancesInternal(
                loanAuction.asset,
                cAsset,
                loanAuction.lender,
                fullBidBuyOutAmount,
                interestAndPremiumOwedToLender,
                loanAuction.amountDrawn
            );
        }
        // else process as ETH
        else if (
            loanAuction.asset == 0x0000000000000000000000000000000000000000
        ) {
            // require transaction has enough value to pay out current lender and protocol premium fee
            require(
                msg.value >= fullBidBuyOutAmount,
                "Transaction must contain enough value to pay out currentlender plus premium"
            );

            _payEthAndUpdateBalancesInternal(
                cAsset,
                loanAuction.lender,
                msg.value,
                msgValueMinusProtocolPremiumFee,
                interestAndPremiumOwedToLender,
                loanAuction.amountDrawn
            );
        }

        // save temporary current historicInterest
        uint256 currentHistoricInterest = loanAuction.historicInterest;

        // update LoanAuction struct
        loanAuction.lender = msg.sender;
        loanAuction.loanAmount = offer.loanAmount;
        loanAuction.interestRate = offer.interestRate;
        loanAuction.loanDuration = offer.duration;
        loanAuction.bestBidTime = block.timestamp;
        loanAuction.historicInterest = currentHistoricInterest + lenderInterest;
    }

    // this internal functions handles transfer of erc20 tokens and updating lender balances for buyOutLoan, repayRemainingLoan, and partialRepayment functions
    function _payErc20AndUpdateBalancesInternal(
        address asset,
        address cAsset,
        address lender,
        uint256 fullAmount,
        uint256 interestAndPremiumAmount,
        uint256 paymentAmount
    ) internal returns (uint256) {
        // Create a reference to the underlying asset contract, like DAI.
        Erc20 underlying = Erc20(asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(cAsset);

        // instantiate interestAndPremiumTokens
        uint256 interestAndPremiumTokens;
        // instantiate paymentTokens
        uint256 paymentTokens;

        // should have require statement to ensure tranfer is successful before proceeding
        // transferFrom ERC20 from depositors address
        underlying.transferFrom(msg.sender, address(this), fullAmount);

        // instantiate MintLocalVars
        MintLocalVars memory vars;

        // set exchange rate from erc20 to cErc20
        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        // convert interestAndPremiumAmount to cErc20
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

        // convert paymentAmount to cErc20
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
        // mint cTokens
        cToken.mint(fullAmount);

        // update the lenders utilized balance
        utilizedCErc20Balances[cAsset][lender] -= paymentTokens;

        // update the lenders total balance
        cErc20Balances[cAsset][lender] += interestAndPremiumTokens;

        return 0;
    }

    // this internal functions handles transfer of Eth and updating lender balances for buyOutLoan, repayRemainingLoan, and partialRepayment functions
    function _payEthAndUpdateBalancesInternal(
        address cAsset,
        address lender,
        uint256 msgValue,
        uint256 msgValueMinusFee,
        uint256 interestAndPremiumAmount,
        uint256 paymentAmount
    ) internal returns (uint256) {
        // Create a reference to the corresponding cToken contract, like cDAI
        CEth cToken = CEth(cAsset);

        // instantiate interestAndPremiumTokens
        uint256 interestAndPremiumTokens;
        // instantiate paymentTokens
        uint256 paymentTokens;
        // instantiate msgValueTokens
        uint256 msgValueTokens;

        //Instantiate MintLocalVars
        MintLocalVars memory vars;

        // set exchange rate from eth to cErc20
        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        // convert msgValueMinusFee to cErc20
        // This accounts for any extra Eth sent to function, since cant use transferFrom for exact amount
        // Any extra value is given to lender
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

        // convert interestAndPremiumAmount to cErc20
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

        // convert paymentAmount to cErc20
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

        // update the lenders utilized balance
        utilizedCErc20Balances[cAsset][lender] -= paymentAmount;

        // update the lenders total balance
        cErc20Balances[cAsset][lender] += (interestAndPremiumTokens +
            mintDelta);

        return 0;
    }

    // Cancel a signature based bid or ask on chain
    function withdrawBidOrAsk(Offer memory offer, bytes memory signature)
        public
    {
        // require signature is still valid. This also ensures the signature is not utilized in an active loan
        require(
            cancelledOrFinalized[signature] == false,
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
        cancelledOrFinalized[signature] = true;
    }

    function drawLoanTime(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawTime
    ) public whenNotPaused nonReentrant {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[nftContractAddress][
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

        // Require timeDrawn is less than the loanDuration. Ensures there is time available to draw
        require(
            loanAuction.timeDrawn < loanAuction.loanDuration,
            "Draw Time amount not available"
        );

        // Require that drawTime + timeDrawn does not exceed loanDuration
        require(
            (drawTime + loanAuction.timeDrawn) <= loanAuction.loanDuration,
            "Total Time drawn must not exceed best bid duration"
        );

        // set timeDrawn
        loanAuction.timeDrawn += drawTime;
    }

    function drawLoanAmount(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawAmount
    ) public whenNotPaused nonReentrant {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[nftContractAddress][
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
            loanAuction.amountDrawn < loanAuction.loanAmount,
            "Draw down amount not available"
        );

        // Require that drawAmount does not exceed loanAmount
        require(
            (drawAmount + loanAuction.amountDrawn) <= loanAuction.loanAmount,
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
        if (loanAuction.asset != 0x0000000000000000000000000000000000000000) {
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
            loanAuction.asset == 0x0000000000000000000000000000000000000000
        ) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferEthInternal(
                cAsset,
                drawAmountMinusFee,
                loanAuction.nftOwner
            );
        }

        emit LoanDrawn(
            nftContractAddress,
            nftId,
            drawAmount,
            drawAmountMinusFee,
            loanAuction.amountDrawn
        );
    }

    // enables borrowers to repay their full loan to a lender and regain full ownership of their NFT
    function repayRemainingLoan(address nftContractAddress, uint256 nftId)
        public
        payable
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[nftContractAddress][
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

        // get required repayment
        uint256 fullRepayment = interestOwedToLender + loanAuction.amountDrawn;

        // if asset is not 0x0 process as Erc20
        if (loanAuction.asset != 0x0000000000000000000000000000000000000000) {
            // protocolPremiumFee is taken here. Full amount is minted to this contract address' balance in Compound and amount owed to lender is updated in their balance. The delta is the protocol premium fee.
            _payErc20AndUpdateBalancesInternal(
                loanAuction.asset,
                cAsset,
                loanAuction.lender,
                fullRepayment,
                interestOwedToLender,
                loanAuction.amountDrawn
            );
        }
        // else process as ETH
        else if (
            loanAuction.asset == 0x0000000000000000000000000000000000000000
        ) {
            // check that transaction covers the full value of the loan
            require(
                msg.value >= fullRepayment,
                "Must repay full amount of loan drawn plus interest. Account for additional time for interest."
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
        loanAuction.nftOwner = 0x0000000000000000000000000000000000000000;
        loanAuction.lender = 0x0000000000000000000000000000000000000000;
        loanAuction.asset = 0x0000000000000000000000000000000000000000;
        loanAuction.loanAmount = 0;
        loanAuction.interestRate = 0;
        loanAuction.loanDuration = 0;
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
    ) public payable whenNotPaused nonReentrant {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[nftContractAddress][
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

        // calculate paymentAmount
        uint256 paymentAmount = partialAmount - interestAmount;

        // if asset is not 0x0 process as Erc20
        if (loanAuction.asset != 0x0000000000000000000000000000000000000000) {
            _payErc20AndUpdateBalancesInternal(
                loanAuction.asset,
                cAsset,
                loanAuction.lender,
                partialAmount,
                interestAmount,
                paymentAmount
            );
        }
        // else process as ETH
        else if (
            loanAuction.asset == 0x0000000000000000000000000000000000000000
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
    }

    // allows anyone to seize an asset of a past due loan on behalf on the lender
    function seizeAsset(address nftContractAddress, uint256 nftId)
        public
        whenNotPaused
        nonReentrant
    {
        // instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[nftContractAddress][
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
        loanAuction.nftOwner = 0x0000000000000000000000000000000000000000;
        loanAuction.lender = 0x0000000000000000000000000000000000000000;
        loanAuction.asset = 0x0000000000000000000000000000000000000000;
        loanAuction.loanAmount = 0;
        loanAuction.interestRate = 0;
        loanAuction.loanDuration = 0;
        loanAuction.bestBidTime = 0;
        loanAuction.loanExecutedTime = 0;
        loanAuction.historicInterest = 0;
        loanAuction.amountDrawn = 0;
        loanAuction.timeDrawn = 0;
        loanAuction.fixedTerms = false;

        // update lenders utilized balance
        utilizedCErc20Balances[cAsset][loanAuction.lender] -= loanAuction
            .amountDrawn;

        // update lenders total balance
        cErc20Balances[cAsset][loanAuction.lender] -= loanAuction.amountDrawn;

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
        public
        view
        returns (address)
    {
        // instantiate LoanAuction Struct
        LoanAuction memory loanAuction = loanAuctions[nftContractAddress][
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
        LoanAuction memory loanAuction = loanAuctions[nftContractAddress][
            nftId
        ];

        // Require that loan is active
        require(
            loanAuction.loanExecutedTime != 0,
            "Loan must be active to calculate interest accrued"
        );

        // calculate seconds as lender
        uint256 secondsAslender = block.timestamp - loanAuction.bestBidTime;

        // percent of total loan time as Lender
        uint256 percentOfLoanTimeAsLender = SafeMath.div(
            loanAuction.timeDrawn,
            secondsAslender
        );

        // percent of value of amountDrawn earned
        uint256 percentOfValue = SafeMath.mul(
            loanAuction.amountDrawn,
            percentOfLoanTimeAsLender
        );

        // Interest rate
        uint256 interestRate = SafeMath.div(loanAuction.interestRate, 100);
        // Calculate interest amount
        uint256 interestAmount = SafeMath.mul(interestRate, percentOfValue);
        // return interest amount
        return interestAmount;
    }

    // calculate the fullRepayment of a loan
    function calculateFullRepayment(address nftContractAddress, uint256 nftId)
        public
        view
        returns (uint256)
    {
        LoanAuction memory loanAuction = loanAuctions[nftContractAddress][
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
        LoanAuction memory loanAuction = loanAuctions[nftContractAddress][
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
            (loanAuction.amountDrawn * buyOutPremiumLenderPrecentage) +
            (loanAuction.amountDrawn * buyOutPremiumProtocolPrecentage);
    }

    function updateLoanDrawFee(uint256 newFeeAmount) external onlyOwner {
        loanDrawFeeProtocolPercentage = SafeMath.div(newFeeAmount, 100);

        // emit newLoanDrawFeeAmount();
    }

    function updateBuyOutPremiumLenderPrecentage(
        uint256 newPremiumLenderPrecentage
    ) external onlyOwner {
        buyOutPremiumLenderPrecentage = SafeMath.div(
            newPremiumLenderPrecentage,
            1000
        );

        // emit newPremiumLenderPercentage();
    }

    function updateBuyOutPremiumProtocolPrecentage(
        uint256 newPremiumProtocolPrecentage
    ) external onlyOwner {
        buyOutPremiumProtocolPrecentage = SafeMath.div(
            newPremiumProtocolPrecentage,
            1000
        );

        // emit newPremiumProtocolPercentage();
    }

    // @notice By calling 'revert' in the fallback function, we prevent anyone
    //         from accidentally sending ether directly to this contract.
    fallback() external payable {
        revert();
    }
}

// still needed:
// 1. Events
// 2. SafeMath
// 3. Ownable, Upgradeable, etc.
// 4. Diamond Pattern
// 5. Admin functions
