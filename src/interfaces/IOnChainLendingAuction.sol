//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ILiquidityProviders.sol";

interface ISignatureLendingAuction is ILiquidityProviders {
    // Structs

    struct LoanAuction {
        // NFT owner
        address nftOwner;
        // Current lender
        address lender;
        // loan asset
        address asset; // 0x0 in active loan denotes ETH
        // loan amount
        uint256 amount;
        // loan interest rate
        uint256 interestRate;
        // loan duration of loan in number of seconds
        uint256 duration;
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
        // offer creator
        address creator;
        // offer NFT contract address
        address nftContractAddress;
        // offer NFT ID
        uint256 nftId; // 0 if floorTerm is true
        // offer asset type
        address asset;
        // offer loan amount
        uint256 amount;
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

    struct Bid {
        // Lender
        address lender;
        // offer NFT contract address
        address nftContractAddress;
        // offer NFT ID
        uint256 nftId; // 0 if floorTerm is true
        // offer asset type
        address asset;
        // offer loan amount
        uint256 amount;
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

    struct Ask {
        // nftOwner
        address nftOwner;
        // offer NFT contract address
        address nftContractAddress;
        // offer NFT ID
        uint256 nftId; // 0 if floorTerm is true
        // offer asset type
        address asset;
        // offer loan amount
        uint256 amount;
        // offer interest rate
        uint256 interestRate;
        // offer loan duration
        uint256 duration;
        // offer expiration
        uint256 expiration;
        // is loan offer fixed terms or open for perpetual auction
        bool fixedTerms;
    }

    // Events

    event LoanExecuted(
        address lender,
        address nftOwner,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address asset,
        uint256 amount,
        uint256 interestRate,
        uint256 duration
    );

    event LoanBuyOut(
        address lender,
        address nftOwner,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address asset,
        uint256 amount,
        uint256 interestRate,
        uint256 duration
    );

    // cancellation sig event
    event BidAskCancelled(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        bytes signature
    );

    // finalize sig event
    event BidAskFinalized(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        bytes signature
    );

    event TimeDrawn(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        uint256 drawTime,
        uint256 totalDrawn
    );

    event AmountDrawn(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        uint256 drawAmount,
        uint256 drawAmountMinusFee,
        uint256 totalDrawn
    );

    event LoanRepaidInFull(
        address indexed nftContractAddress,
        uint256 indexed nftId
    );

    event PartialRepayment(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address asset,
        uint256 amount
    );

    event AssetSeized(
        address indexed nftContractAddress,
        uint256 indexed nftId
    );

    // Functions

    function loanDrawFeeProtocolPercentage() external view returns (uint256);

    function buyOutPremiumLenderPercentage() external view returns (uint256);

    function buyOutPremiumProtocolPercentage() external view returns (uint256);

    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory auction);

    function getOfferStatus(bytes calldata signature)
        external
        view
        returns (bool status);

    function getOfferHash(Offer calldata offer)
        external
        view
        returns (bytes32 offerhash);

    function getOfferSigner(bytes32 offerHash, bytes memory signature)
        external
        pure
        returns (address signer);

    function executeLoanByBid(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId
    ) external payable;

    function executeLoanByAsk(Offer calldata offer, bytes calldata signature)
        external
        payable;

    function refinanceByBorrower(Offer calldata offer, bytes calldata signature)
        external
        payable;

    function refinanceByLender(Offer calldata offer) external payable;

    function withdrawBidOrAsk(Offer calldata offer, bytes calldata signature)
        external;

    function drawLoanTime(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawTime
    ) external;

    function drawAmount(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawAmount
    ) external;

    function repayRemainingLoan(address nftContractAddress, uint256 nftId)
        external
        payable
        returns (uint256);

    function partialPayment(
        address nftContractAddress,
        uint256 nftId,
        uint256 partialAmount
    ) external payable;

    function seizeAsset(address nftContractAddress, uint256 nftId) external;

    function ownerOf(address nftContractAddress, uint256 nftId)
        external
        view
        returns (address);

    function calculateInterestAccruedBylender(
        address nftContractAddress,
        uint256 nftId
    ) external view returns (uint256);

    function calculateFullRepayment(address nftContractAddress, uint256 nftId)
        external
        view
        returns (uint256);

    function calculateFullBidBuyOut(address nftContractAddress, uint256 nftId)
        external
        view
        returns (uint256);

    function updateLoanDrawFee(uint256 newFeeAmount) external;

    function updateBuyOutPremiumLenderPercentage(
        uint256 newPremiumLenderPercentage
    ) external;

    function updateBuyOutPremiumProtocolPercentage(
        uint256 newPremiumProtocolPercentage
    ) external;
}
