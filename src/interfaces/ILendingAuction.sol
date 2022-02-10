//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./ILiquidityProviders.sol";

interface ILendingAuction is ILiquidityProviders {
    // Structs

    struct LoanAuction {
        // NFT owner
        address nftOwner;
        // Current lender
        address lender;
        // loan asset
        address asset; // 0x0 in active loan denotes ETH
        // loan interest rate in basis points for the loan duration
        uint64 interestRateBps;
        // boolean of whether fixedTerms has been accepted by a borrower
        // if fixedTerms == true could mint an NFT that represents that loan to enable packaging and reselling.
        bool fixedTerms;
        // loan amount
        uint256 amount;
        // loan duration of loan in number of seconds
        uint256 duration;
        // timestamp of loan execution
        uint256 loanExecutedTime;
        // timestamp of start of interest acummulation. Is reset when a new lender takes over the loan or the borrower makes a partial repayment.
        uint256 timeOfInterestStart;
        // cumulative interest of varying rates paid by new lenders to buy out the loan auction
        uint256 historicLenderInterest;
        // cumulative interest of varying rates accrued by the protocol. To be repaid at the end of the loan.
        uint256 historicProtocolInterest;
        // amount withdrawn by the nftOwner. This is the amount they will pay interest on, with this value as minimum
        uint256 amountDrawn;
        // time withdrawn by the nftOwner. This is the time they will pay interest on, with this value as minimum
        uint256 timeDrawn;
    }

    struct Offer {
        // Offer creator
        address creator;
        // offer NFT contract address
        address nftContractAddress;
        // offer interest rate in basis points for the loan duration
        uint64 interestRateBps;
        // is loan offer fixed terms or open for perpetual auction
        bool fixedTerms;
        // is offer for single NFT or for every NFT in a collection
        bool floorTerm;
        // offer NFT ID
        uint256 nftId; // ignored if floorTerm is true
        // offer asset type
        address asset;
        // offer loan amount
        uint256 amount;
        // offer loan duration
        uint256 duration;
        // offer expiration
        uint256 expiration;
    }

    // Structure representing an offer book per NFT or floor term
    struct OfferBook {
        bytes32[] keys;
        mapping(bytes32 => Offer) offers;
        mapping(bytes32 => uint256) indexOf;
        mapping(bytes32 => bool) inserted;
    }

    struct InterestAndPaymentVars {
        uint256 currentLenderInterest;
        uint256 currentProtocolInterest;
        uint256 interestAndPremiumOwedToCurrentLender;
        uint256 fullAmount;
    }

    struct TokenVars {
        uint256 lenderInterestAndPremiumTokens;
        uint256 protocolInterestAndPremiumTokens;
        uint256 paymentTokens;
        uint256 msgValueTokens;
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

    event LoanRefinance(
        address lender,
        address nftOwner,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        Offer offer
    );

    // cancellation sig event
    event SigOfferCancelled(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        bytes signature
    );

    // finalize sig event
    event SigOfferFinalized(
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

    event NewOffer(Offer offer, bytes32 offerHash);

    event OfferRemoved(Offer offer, bytes32 offerHash);

    // Functions
    function loanDrawFeeProtocolBps() external view returns (uint64);

    function refinancePremiumLenderBps() external view returns (uint64);

    function refinancePremiumProtocolBps() external view returns (uint64);

    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory auction);

    function getOfferSignatureStatus(bytes calldata signature)
        external
        view
        returns (bool status);

    function withdrawOfferSignature(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bytes calldata signature
    ) external;

    function getOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external view returns (Offer memory offer);

    function getOfferAtIndex(
        address nftContractAddress,
        uint256 nftId,
        uint256 index,
        bool floorTerm
    ) external view returns (Offer memory offer);

    function size(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm
    ) external view returns (uint256);

    function createOffer(Offer calldata offer) external;

    function removeOffer(
        address nftContractAddress,
        bool floorTerm,
        uint256 nftId,
        bytes32 offerHash
    ) external;

    function executeLoanByBorrower(
        address nftContractAddress,
        bool floorTerm,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    // TODO(nftID is duplicate here, the data is already in the offer struct)
    // nftId is required in this function to serve floor offers. A floor offer can serve any nftId,
    // so one is provided to this function, and if the nftId at that nftContractAddress is owned by msg.sender then the loan is executed
    function executeLoanByBorrowerSignature(
        Offer calldata offer,
        bytes memory signature,
        uint256 nftId
    ) external payable;

    function executeLoanByLender(
        address nftContractAddress,
        bool floorTerm,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    function executeLoanByLenderSignature(
        Offer calldata offer,
        bytes calldata signature
    ) external payable;

    function refinanceByBorrower(
        address nftContractAddress,
        bool floorTerm,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    // TODO(Test)
    // TODO(nftID is duplicate here, the data is already in the offer struct)
    // nftId is required in this function to serve floor offers. A floor offer can serve any nftId,
    // so one is provided to this function, and if the nftId at that nftContractAddress is owned by msg.sender then the loan is executed
    function refinanceByBorrowerSignature(
        Offer calldata offer,
        bytes memory signature,
        uint256 nftId
    ) external payable;

    // TODO(This function is broken, fix)
    function refinanceByLender(Offer calldata offer) external payable;

    function drawLoanTime(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawTime
    ) external;

    function drawLoanAmount(
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

    function calculateInterestAccrued(address nftContractAddress, uint256 nftId)
        external
        view
        returns (uint256, uint256);

    function calculateFullRepayment(address nftContractAddress, uint256 nftId)
        external
        view
        returns (uint256);

    // TODO(Test)
    function calculateFullRefinanceByLender(
        address nftContractAddress,
        uint256 nftId
    ) external view returns (uint256);

    function updateLoanDrawProtocolFee(uint64 newLoanDrawProtocolFeeBps)
        external;

    function updateRefinancePremiumLenderFee(uint64 newPremiumLenderBps)
        external;

    function updateRefinancePremiumProtocolFee(uint64 newPremiumProtocolBps)
        external;
}
