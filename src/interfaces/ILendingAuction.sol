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
        // loan amount
        uint256 amount;
        // loan interest rate
        uint256 interestRate;
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
        // boolean of whether fixedTerms has been accepted by a borrower
        // if fixedTerms == true could mint an NFT that represents that loan to enable packaging and reselling.
        bool fixedTerms;
    }

    struct Offer {
        // Offer creator
        address creator;
        // offer NFT contract address
        address nftContractAddress;
        // offer NFT ID
        uint256 nftId; // ignored if floorTerm is true
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

    // Iterable mapping from address to uint;
    struct OfferBook {
        bytes32[] keys;
        mapping(bytes32 => Offer) offers;
        mapping(bytes32 => uint256) indexOf;
        mapping(bytes32 => bool) inserted;
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
        address asset,
        uint256 amount,
        uint256 interestRate,
        uint256 duration
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

    event NewOffer(
        address creator,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address asset,
        uint256 amount,
        uint256 interestRate,
        uint256 duration,
        uint256 expiration,
        bool fixedTerms,
        bool floorTerm,
        bytes32 offerHash
    );

    event OfferRemoved(
        address creator,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address asset,
        uint256 amount,
        uint256 interestRate,
        uint256 duration,
        uint256 expiration,
        bool fixedTerms,
        bool floorTerm,
        bytes32 offerHash
    );

    // Functions

    function protocolDrawFeePercentage() external view returns (uint256);

    function refinancePremiumLenderPercentage() external view returns (uint256);

    function refinancePremiumProtocolPercentage()
        external
        view
        returns (uint256);

    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory auction);

    function getOfferHash(Offer calldata offer)
        external
        view
        returns (bytes32 offerhash);

    function getSignatureOfferStatus(bytes calldata signature)
        external
        view
        returns (bool status);

    function getOfferSigner(bytes32 offerHash, bytes memory signature)
        external
        pure
        returns (address signer);

    function withdrawBidOrAsk(Offer calldata offer, bytes calldata signature)
        external;

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

    function createFloorOffer(address nftContractAddress, Offer memory offer)
        external;

    function createNftOffer(
        address nftContractAddress,
        uint256 nftId,
        Offer memory offer
    ) external;

    function removeFloorOffer(address nftContractAddress, bytes32 offerHash)
        external;

    function removeNftOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external;

    function sigExecuteLoanByBorrower(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId
    ) external payable;

    function chainExecuteLoanByBorrowerFloor(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    function chainExecuteLoanByBorrowerNft(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    function sigExecuteLoanByLender(
        Offer calldata offer,
        bytes calldata signature
    ) external payable;

    function chainExecuteLoanByLender(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    function sigRefinanceByBorrower(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId
    ) external payable;

    function chainRefinanceByBorrowerFloor(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    function chainRefinanceByBorrowerNft(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

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

    function ownerOf(address nftContractAddress, uint256 nftId)
        external
        view
        returns (address);

    function calculateInterestAccrued(
        address nftContractAddress,
        uint256 nftId,
        bool lenderOrProtocol
    ) external view returns (uint256);

    function calculateFullRepayment(address nftContractAddress, uint256 nftId)
        external
        view
        returns (uint256);

    function calculateFullRefinanceByLender(
        address nftContractAddress,
        uint256 nftId
    ) external view returns (uint256);

    function updateLoanDrawFee(uint256 newFeeAmount) external;

    function updateRefinancePremiumLenderPercentage(
        uint256 newPremiumLenderPercentage
    ) external;

    function updateRefinancePremiumProtocolPercentage(
        uint256 newPremiumProtocolPercentage
    ) external;
}
