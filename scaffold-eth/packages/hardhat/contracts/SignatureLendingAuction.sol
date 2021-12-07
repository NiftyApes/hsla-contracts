pragma solidity ^0.8.2;
//SPDX-License-Identifier: MIT

import "./LiquidityProviders.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SignatureLendingAuction is LiquidityProviders {
    // Solidity 0.8.x provides safe math, but uses an invalid opcode error which comsumes all gas. SafeMath uses revert which returns all gas.
    using SafeMath for uint256;
    using ECDSA for bytes32;

    // ---------- STRUCTS --------------- //

    struct LoanAuction {
        // NFT owner 
        address nftOwner;
        // Current bestBidder
        address bestBidder;
        // ask loan amount
        // uint256 askLoanAmount; // I believe we can remove this since we are forcing transferring of funds at the time of loan execution in this implementation. 
        // best bid asset
        address bestBidAsset; // 0x0 in active loan denotes ETH
        // best bid cAsset
        address bestBidCAsset; // 0x0 in active loan denotes ETH
        // best bid loan amount. includes accumulated interest in an active loan.
        uint256 bestBidLoanAmount;
        // best bid interest rate
        uint256 bestBidInterestRate;
        // best bid duration of loan in number of seconds
        uint256 bestBidLoanDuration;
        // timestamp of bestBid
        uint256 bestBidTime;
        // timestamp of loan execution
        uint256 loanExecutedTime;
        // timestamp of loanAuction completion. loanStartTime + bestBidLoanDuration
        uint256 loanEndTime;
        // Cumulative interest of varying rates paid by new bestBidders to buy out the loan auction
        uint256 historicInterest;
        // amount withdrawn by the nftOwner. This is the amount they will pay interest on, with askLoanAmount as minimum.
        uint256 loanAmountDrawn;
        // boolean of whether fixedTerms has been accepted by a borrower
        // if fixedTerms == true could mint an NFT that represents that loan to enable packing and reselling.
        bool fixedTerms;
    }

    struct Offer {
        address nftContractAddress;
        uint256 nftId; // 0 if floorTerm is true
        address asset;
        address cAsset;
        uint256 loanAmount;
        uint256 interestRate;
        uint256 duration;
        bool fixedTerms;
        bool floorTerm;
    }

    // need to see how OpenSea tracks cancelled bid and ask signatures

    // ---------- STATE VARIABLES --------------- //

    // Mapping of nftId to nftContractAddress to LoanAuction struct
    mapping(address => mapping(uint256 => LoanAuction)) public loanAuctions;

    /* Cancelled / finalized orders, by signature. */
    mapping(bytes => bool) public cancelledOrFinalized;

    // need admin function to update fees
    uint256 loanDrawFee = SafeMath.div(1, 100);
    uint256 buyOutPremium = SafeMath.div(1, 100);

    // All fees are transfered to this smart contract

    // ---------- EVENTS --------------- //

    // New Best Bid event
    event NewBestBid(
        address _bestBidder,
        address indexed _nftContractAddress,
        uint256 indexed _nftId,
        uint256 _bestBidLoanAmount,
        uint256 _bestBidInterestRate,
        uint256 _bestBidLoanDuration
    );

    event BestBidWithdrawn(
        address indexed _nftContractAddress,
        uint256 indexed _nftId
    );

    event NewAsk(
        address indexed _nftContractAddress,
        uint256 indexed _nftId,
        uint256 _askLoanAmount,
        uint256 _askInterestRate,
        uint256 _askLoanDuration
    );

    event AskWithdrawn(
        address indexed _nftContractAddress,
        uint256 indexed _nftId
    );

    event LoanExecuted(
        address _bestBidder,
        address _nftOwner,
        address indexed _nftContractAddress,
        uint256 indexed _nftId,
        uint256 _bestBidLoanAmount,
        uint256 _bestBidInterestRate,
        uint256 _bestBidLoanDuration
    );

    event LoanDrawn(
        address indexed _nftContractAddress,
        uint256 indexed _nftId,
        uint256 _drawAmount,
        uint256 _drawAmountMinusFee,
        uint256 _totalDrawn
    );

    event LoanRepaidInFull(
        address indexed _nftContractAddress,
        uint256 indexed _nftId
    );

    event AssetSeized(
        address indexed _nftContractAddress,
        uint256 indexed _nftId
    );

    // ---------- MODIFIERS --------------- //

    modifier isNFTOwner(address _nftContractAddress, uint256 _nftId) {
        _;
    }

    // ---------- FUNCTIONS -------------- //

    // ideally this hash can be generated on the frontend, stored in the backend, and provided to functions to reduce computation
    // given the offer details, generate a hash and try to kind of follow the eip-191 standard
    function getOfferHash(Offer memory signedOffer)
        public
        view
        returns (bytes32 _offerhash)
    {
        // originally 'byte' values, but solidity compiler was throwing error. If cant match signature investigate this.
        // abi.encodePacked(
        // byte(0x19),
        // byte(0),

        return
            keccak256(
                abi.encodePacked(
                    bytes1(0x19),
                    bytes1(0),
                    address(this),
                    signedOffer.nftContractAddress,
                    signedOffer.nftId,
                    signedOffer.asset,
                    signedOffer.cAsset,
                    signedOffer.loanAmount,
                    signedOffer.interestRate,
                    signedOffer.duration,
                    signedOffer.fixedTerms,
                    signedOffer.floorTerm
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

    // might need acceptBid function that allows a borrower to accept an offer with worse terms during an active loan acceptBidActiveLoan an active loan
    // would need to make sure principle plus interest and premium is settled

    // might need an executeLoanByBid and executeLoanByAsk
    function executeLoanByBid(
        Offer memory signedOffer,
        // bytes offerHash,
        bytes memory signature,
        uint256 nftId // nftId should match signedOffer.nftId if floorTerm false, nftId should not match if floorTerm true. Need to provide as function parameter to pass nftId with floor terms.
    ) public returns (uint256) {
        // require signature has not been cancelled/bid withdrawn
        require(
            cancelledOrFinalized[signature] == false,
            "Cannot execute bid or ask. Signature has been cancelled or previously finalized."
        );

        // get nft owner
        address nftOwner = IERC721(signedOffer.nftContractAddress).ownerOf(
            nftId
        );

        // require msg.sender is the nftOwner. This ensures function submitted nftId is valid to execute against
        require(
            nftOwner == msg.sender,
            "Msg.sender must be the owner of nftId to executeLoanByBid"
        );

        // ideally calculated, stored, and provided as parameter to save computation
        bytes32 offerHash = getOfferHash(signedOffer);

        // recover singer and confirm signature terms with function submitted terms
        // We know the signer must be the lender because msg.sender must be the nftOwner/borrower
        address lender = getOfferSigner(offerHash, signature);

        // if floorTerm is false
        if (signedOffer.floorTerm == false) {
            // require nftId == sigNftId
            require(
                nftId == signedOffer.nftId,
                "Function submitted nftId must match the signed offer nftId"
            );

            _executeLoanByBidInternal(
                signedOffer,
                nftId,
                lender,
                nftOwner,
                signature
            );
        }

        // if floorTerm is true
        if (signedOffer.floorTerm == true) {
            // requrie msg.sender or signer is the nftOwner of any nft at nftContractAddress
            _executeLoanByBidInternal(
                signedOffer,
                nftId,
                lender,
                nftOwner,
                signature
            );
        }

        return 0;
    }

    function _executeLoanByBidInternal(
        Offer memory signedOffer,
        uint256 nftId,
        address lender,
        address nftOwner, // 10 variables
        bytes memory signature
    ) internal returns (uint256) {
        // checks done in executeLoanByBid

        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[
            signedOffer.nftContractAddress
        ][nftId];

        // if loan is not active execute intial loan
        if (loanAuction.loanExecutedTime == 0) {
            // finalize signature
            cancelledOrFinalized[signature] == true;

            // check if lender has sufficient balance and update utilizedBalance
            _checkAndUpdateLenderBalanceInternal(
                signedOffer.cAsset,
                signedOffer.loanAmount,
                lender
            );

            // update LoanAuction struct
            loanAuction.nftOwner = nftOwner;
            // loanAuction.askLoanAmount = signedOffer.loanAmount;
            loanAuction.bestBidder = lender;
            loanAuction.bestBidAsset = signedOffer.asset;
            loanAuction.bestBidLoanAmount = signedOffer.loanAmount;
            loanAuction.bestBidInterestRate = signedOffer.interestRate;
            loanAuction.bestBidLoanDuration = signedOffer.duration;
            loanAuction.bestBidTime = block.timestamp;
            loanAuction.loanExecutedTime = block.timestamp;
            loanAuction.loanEndTime = block.timestamp + signedOffer.duration;
            loanAuction.loanAmountDrawn = signedOffer.loanAmount;
            loanAuction.fixedTerms = signedOffer.fixedTerms;

            // transferFrom NFT from nftOwner to contract
            IERC721(signedOffer.nftContractAddress).transferFrom(
                nftOwner,
                address(this),
                nftId
            );

            // if asset is not 0x0 process as Erc20
            if (
                signedOffer.asset != 0x0000000000000000000000000000000000000000
            ) {
                // redeem cTokens and transfer underlying to borrower
                _redeemAndTransferErc20Internal(
                    signedOffer.asset,
                    signedOffer.cAsset,
                    signedOffer.loanAmount,
                    nftOwner
                );
            }
            // else process as ETH
            else if (
                signedOffer.asset == 0x0000000000000000000000000000000000000000
            ) {
                // redeem cTokens and transfer underlying to borrower
                _redeemAndTransferEthInternal(
                    signedOffer.cAsset,
                    signedOffer.loanAmount,
                    nftOwner
                );
            }
        }
        // else if loan is active, create path for borrower to pay off loan and accept new bid
        else if (loanAuction.loanExecutedTime != 0) {
            // may be better to refactor and create specific bestBidBuyOutbyborrower function
            // calculate fullRepayment and intiate new executeLoanByBid
            repayRemainingLoan(signedOffer.nftContractAddress, nftId);
            _executeLoanByBidInternal(
                signedOffer,
                nftId,
                lender,
                nftOwner,
                signature
            );
        }

        return 0;
    }

    // Submitted by a lender to execute a loan by an ask
    function executeLoanByAsk(
        Offer memory signedOffer,
        // bytes offerHash,
        bytes memory signature
    ) public {
        // require signature has not been cancelled/bid withdrawn
        require(
            cancelledOrFinalized[signature] == false,
            "Cannot execute bid or ask. Signature has been cancelled or previously finalized."
        );

        // get nft owner
        address nftOwner = IERC721(signedOffer.nftContractAddress).ownerOf(
            signedOffer.nftId
        );

        // ideally calculated, stored, and provided as parameter to save computation
        bytes32 offerHash = getOfferHash(signedOffer);

        // recover singer and confirm signature terms with function submitted terms
        // We know the signer must be the lender because msg.sender must be the nftOwner/borrower
        address borrower = getOfferSigner(offerHash, signature);

        // require msg.sender is the nftOwner. This ensures function submitted nftId is valid to execute against
        require(
            nftOwner == borrower,
            "Borrower must be the owner of nftId to executeLoanByBid"
        );

        _executeLoanByAskInternal(signedOffer, msg.sender, nftOwner, signature);
    }

    function _executeLoanByAskInternal(
        Offer memory signedOffer,
        address lender,
        address nftOwner,
        bytes memory signature
    ) internal {
        // checks done in executeLoanByAsk

        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[
            signedOffer.nftContractAddress
        ][signedOffer.nftId];

        // require msg.sender is the nftOwner. This ensures function submitted nftId is valid to execute against
        require(
            loanAuction.loanExecutedTime == 0,
            "Loan is already active. Cannot execute new ask."
        );

        // finalize signature
        cancelledOrFinalized[signature] == true;

        // check if lender has sufficient balance and update utilizedBalance
        _checkAndUpdateLenderBalanceInternal(
            signedOffer.cAsset,
            signedOffer.loanAmount,
            lender
        );

        // update LoanAuction struct
        loanAuction.nftOwner = nftOwner;
        // loanAuction.askLoanAmount = signedOffer.loanAmount;
        loanAuction.bestBidder = lender;
        loanAuction.bestBidAsset = signedOffer.asset;
        loanAuction.bestBidLoanAmount = signedOffer.loanAmount;
        loanAuction.bestBidInterestRate = signedOffer.interestRate;
        loanAuction.bestBidLoanDuration = signedOffer.duration;
        loanAuction.bestBidTime = block.timestamp;
        loanAuction.loanExecutedTime = block.timestamp;
        loanAuction.loanEndTime = block.timestamp + signedOffer.duration;
        loanAuction.loanAmountDrawn = signedOffer.loanAmount;
        loanAuction.fixedTerms = signedOffer.fixedTerms;

        // transferFrom NFT from nftOwner to contract
        IERC721(signedOffer.nftContractAddress).transferFrom(
            nftOwner,
            address(this),
            signedOffer.nftId
        );

        // if asset is not 0x0 process as Erc20
        if (signedOffer.asset != 0x0000000000000000000000000000000000000000) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferErc20Internal(
                signedOffer.asset,
                signedOffer.cAsset,
                signedOffer.loanAmount,
                nftOwner
            );
        }
        // else process as ETH
        else if (
            signedOffer.asset == 0x0000000000000000000000000000000000000000
        ) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferEthInternal(
                signedOffer.cAsset,
                signedOffer.loanAmount,
                nftOwner
            );
        }
    }

    function _redeemAndTransferErc20Internal(
        address asset,
        address cAsset,
        uint256 amount,
        address nftOwner
    ) internal returns (uint256) {
        // Create a reference to the underlying asset contract, like DAI.
        Erc20 underlying = Erc20(asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(cAsset);

        // redeem underlying from cToken to this contract
        cToken.redeemUnderlying(amount);

        // transfer underlying from this contract to borrower
        underlying.transfer(nftOwner, amount);

        return 0;
    }

    function _redeemAndTransferEthInternal(
        address cAsset,
        uint256 amount,
        address nftOwner
    ) internal returns (uint256) {
        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(cAsset);

        // redeem underlying from cToken to this contract
        cToken.redeemUnderlying(amount);

        // Send Eth to borrower
        (bool success, ) = (nftOwner).call{value: amount}("");
        require(success, "Send eth to depositor failed");

        return 0;
    }

    function _checkAndUpdateLenderBalanceInternal(
        address cAsset,
        uint256 amount,
        address lender
    ) internal returns (uint256) {
        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(cAsset);

        //Instantiate RedeemLocalVars
        RedeemLocalVars memory vars;

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

        // require that the lenders balance is sufficent to serve the loan
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

    // when bidding on an executed loan need to work out if new bid extends loanDuration or restarts.
    function buyOutBestBid(
        address _nftContractAddress,
        uint256 _nftId,
        uint256 _bidLoanAmount,
        uint256 _bidInterestRate,
        uint256 _bidLoanDuration
    ) public payable {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        // require loan is active
        // require that terms are parity + 1
        // calculate the interest earned by current bestBidder
        // save temporary current loan terms
        // update terms of loanAuction
        // update histricInterest
        // finalize bid signature
        // pay out principle, interest, and premium
    }

    // Cancel a signature based bid or ask on chain
    function withdrawBidOrAsk(Offer memory signedOffer, bytes memory signature)
        public
    {
        // require signature is still valid. This also ensures the signature is not utilized in an active loan
        require(
            cancelledOrFinalized[signature] == false,
            "Cannot cancel a bid or ask that is already cancelled or finalized."
        );

        // ideally calculated, stored, and provided as parameter to save computation
        bytes32 offerHash = getOfferHash(signedOffer);

        // recover signer
        address signer = getOfferSigner(offerHash, signature);

        // Require that msg.sender is signer of the signature
        require(
            signer == msg.sender,
            "Msg.sender is not the signer of the submitted signature"
        );

        cancelledOrFinalized[signature] = true;
    }

    function drawLoan(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawAmount
    ) public {
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

        // Require loanAmountDrawn is less than the bestBidAmount
        require(
            loanAuction.loanAmountDrawn < loanAuction.bestBidLoanAmount,
            "Draw down amount not available"
        );

        // Require that drawAmount does not exceed bestBidLoanAmount
        require(
            (drawAmount + loanAuction.loanAmountDrawn) <=
                loanAuction.bestBidLoanAmount,
            "Total amount withdrawn must not exceed best bid loan amount"
        );

        _checkAndUpdateLenderBalanceInternal(
            loanAuction.bestBidCAsset,
            drawAmount,
            loanAuction.bestBidder
        );

        // set loanAmountDrawn
        loanAuction.loanAmountDrawn += drawAmount;

        // calculate fee and subtract from drawAmount
        uint256 drawAmountMinusFee = drawAmount - loanDrawFee;

        // transfer funds to treasury or smart contract address

        // if asset is not 0x0 process as Erc20
        if (loanAuction.bestBidAsset != 0x0000000000000000000000000000000000000000) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferErc20Internal(
                loanAuction.bestBidAsset,
                loanAuction.bestBidCAsset,
                drawAmountMinusFee,
                loanAuction.nftOwner
            );
        }
        // else process as ETH
        else if (
            loanAuction.bestBidAsset == 0x0000000000000000000000000000000000000000
        ) {
            // redeem cTokens and transfer underlying to borrower
            _redeemAndTransferEthInternal(
                loanAuction.bestBidCAsset,
                drawAmountMinusFee,
                loanAuction.nftOwner
            );
        }

        emit LoanDrawn(
            nftContractAddress,
            nftId,
            drawAmount,
            drawAmountMinusFee,
            loanAuction.loanAmountDrawn
        );
    }
    

    function repayRemainingLoan(address _nftContractAddress, uint256 _nftId)
        public
        payable
    {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        // get nft owner
        address _nftOwner = loanAuction.nftOwner;

        // temporarily save current bestBidder
        address currentBestBidder = loanAuction.bestBidder;

        // get required repayment
        uint256 fullRepayment = calculateFullRepayment(
            _nftContractAddress,
            _nftId,
            loanAuction.bestBidAsset
        );

        // Require that loan has been executed
        require(
            loanAuction.loanExecutedTime != 0,
            "Cannot repay loan that has not been executed"
        );

        // if asset is not 0x0 process as Erc20
        if (
            loanAuction.bestBidAsset !=
            0x0000000000000000000000000000000000000000
        ) {
            // convet fullRepayment to cTokens and transfer to lender
        }
        // else process as ETH
        else if (
            loanAuction.bestBidAsset ==
            0x0000000000000000000000000000000000000000
        ) {
            // check that transaction covers the full value of the loan
            require(
                msg.value >= fullRepayment,
                "Must repay full amount of loan drawn plus interest. Account for additional time for interest."
            );

            //    convet msg.value to cTokens and transfer to lender
        }

        // reset loanAuction
        loanAuction.nftOwner = 0x0000000000000000000000000000000000000000;
        // loanAuction.askLoanAmount = 0;
        // loanAuction.askInterestRate = 0;
        // loanAuction.askLoanDuration = 0;
        loanAuction.bestBidder = 0x0000000000000000000000000000000000000000;
        loanAuction.bestBidAsset = 0x0000000000000000000000000000000000000000;
        loanAuction.bestBidLoanAmount = 0;
        loanAuction.bestBidInterestRate = 0;
        loanAuction.bestBidLoanDuration = 0;
        loanAuction.bestBidTime = 0;
        loanAuction.loanExecutedTime = 0;
        loanAuction.loanEndTime = 0;
        loanAuction.loanAmountDrawn = 0;

        // transferFrom NFT from contract to nftOwner
        IERC721(_nftContractAddress).transferFrom(
            address(this),
            _nftOwner,
            _nftId
        );
        // if bestBidAsset = 0x0
        // repay eth plus interest to lender
        (bool success, ) = currentBestBidder.call{value: msg.value}("");
        require(success, "Repay bestBidder failed");
        // else transfer erc20 to this contract
        // mint cErc20
        // update lenders utilized balance

        emit LoanRepaidInFull(_nftContractAddress, _nftId);
    }

    // allows anyone to seize an asset of a past due loan on behalf on the bestBidder
    function seizeAsset(address _nftContractAddress, uint256 _nftId) public {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        // temporarily save current bestBidder
        address currentBestBidder = loanAuction.bestBidder;

        // Require that loan has been executed
        require(
            loanAuction.loanExecutedTime != 0,
            "Cannot seize asset for loan that has not been executed"
        );
        // Require that loan has expired
        require(
            block.timestamp >= loanAuction.loanEndTime,
            "Cannot seize asset before the end of the loan"
        );

        // reset loanAuction
        loanAuction.nftOwner = 0x0000000000000000000000000000000000000000;
        // loanAuction.askLoanAmount = 0;
        // loanAuction.askInterestRate = 0;
        // loanAuction.askLoanDuration = 0;
        loanAuction.bestBidder = 0x0000000000000000000000000000000000000000;
        loanAuction.bestBidAsset = 0x0000000000000000000000000000000000000000;
        loanAuction.bestBidLoanAmount = 0;
        loanAuction.bestBidInterestRate = 0;
        loanAuction.bestBidLoanDuration = 0;
        loanAuction.bestBidTime = 0;
        loanAuction.loanExecutedTime = 0;
        loanAuction.loanEndTime = 0;
        loanAuction.loanAmountDrawn = 0;

        // update lenders utilized and total balance

        // transferFrom NFT from contract to bestBidder
        IERC721(_nftContractAddress).transferFrom(
            address(this),
            currentBestBidder,
            _nftId
        );

        emit AssetSeized(_nftContractAddress, _nftId);
    }

    // can you create a contract the is 721 compliant so that LendingAuction are just an extension of existing 721 contracts?
    function ownerOf(address _nftContractAddress, uint256 _nftId)
        public
        view
        returns (address)
    {
        LoanAuction memory loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        return loanAuction.nftOwner;
    }

    // since funds are transferred as soon as match happens but before draw down,
    // need to have case where interest is calculated by askLoanAmount.
    // returns the interest value earned by bestBidder on active loanAmountDrawn
    function calculateInterestAccruedByBestBidder(
        address _nftContractAddress,
        uint256 _nftId,
        uint256 _timeOfInterest
    ) public view returns (uint256) {
        LoanAuction memory loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        uint256 _secondsAsBestBidder;

        // if bestBidtime is before loanExecutedTime
        if (loanAuction.bestBidTime < loanAuction.loanExecutedTime) {
            // calculate seconds as bestBidder
            _secondsAsBestBidder =
                _timeOfInterest -
                loanAuction.loanExecutedTime;
        }
        // if bestBidtime is on or after loanExecutedTime
        else if (loanAuction.bestBidTime >= loanAuction.loanExecutedTime) {
            _secondsAsBestBidder = _timeOfInterest - loanAuction.bestBidTime;
        }

        // Seconds that loan has been active
        uint256 _secondsSinceLoanExecution = block.timestamp -
            loanAuction.loanExecutedTime;
        // percent of total loan time as bestBid
        uint256 _percentOfLoanTimeAsBestBid = SafeMath.div(
            _secondsSinceLoanExecution,
            _secondsAsBestBidder
        );

        uint256 _percentOfValue;

        if (loanAuction.loanAmountDrawn == 0) {
            // percent of value of askLoanAmount earned
            // _percentOfValue = SafeMath.mul(
            //     loanAuction.askLoanAmount,
            //     _percentOfLoanTimeAsBestBid
            // );
        } else if (loanAuction.loanAmountDrawn != 0) {
            // percent of value of loanAmountDrawn earned
            _percentOfValue = SafeMath.mul(
                loanAuction.loanAmountDrawn,
                _percentOfLoanTimeAsBestBid
            );
        }

        // Interest rate
        uint256 _interestRate = SafeMath.div(
            loanAuction.bestBidInterestRate,
            100
        );
        // Calculate interest amount
        uint256 _interestAmount = SafeMath.mul(_interestRate, _percentOfValue);
        // return interest amount
        return _interestAmount;
    }

    // need to ensure that repayment calculates each of the interest amounts for each of the bestBidders and pays out cumulative value
    function calculateFullRepayment(
        address _nftContractAddress,
        uint256 _nftId,
        address asset
    ) public view returns (uint256) {
        LoanAuction memory loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        uint256 bestBidderInterest = calculateInterestAccruedByBestBidder(
            _nftContractAddress,
            _nftId,
            block.timestamp
        );

        return
            loanAuction.loanAmountDrawn +
            loanAuction.historicInterest +
            bestBidderInterest;
    }

    // @notice By calling 'revert' in the fallback function, we prevent anyone
    //         from accidentally sending funds directly to this contract.
    // function() external payable {
    //     revert();
    // }
}
