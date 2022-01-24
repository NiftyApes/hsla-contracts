//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ILiquidityProviders.sol";

interface IChainLendingAuction is ILiquidityProviders {
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
        bool floorTerm
    );

    // Functions

    function loanDrawFeeProtocolPercentage() external view returns (uint256);

    function buyOutPremiumLenderPercentage() external view returns (uint256);

    function buyOutPremiumProtocolPercentage() external view returns (uint256);

    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory auction);

    function getOfferHash(Offer calldata offer)
        external
        view
        returns (bytes32 offerhash);

    function getSignatureStatus(bytes calldata signature)
        external
        view
        returns (bool status);

    function getOfferSigner(bytes32 offerHash, bytes memory signature)
        external
        pure
        returns (address signer);

    function getOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external view returns (Offer memory offer);

    function getOfferAtIndex(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm,
        uint256 index
    ) external view returns (bytes32);

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

    function removeFloorOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external;

    function removeNftOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external;

    function sigExecuteLoanByBid(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId
    ) external payable;

    function chainExecuteLoanByFloorBid(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    function chainExecuteLoanByNftBid(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    function sigExecuteLoanByAsk(Offer calldata offer, bytes calldata signature)
        external
        payable;

    function chainExecuteLoanByAsk(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    function sigRefinanceByBorrower(
        Offer calldata offer,
        bytes calldata signature
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
