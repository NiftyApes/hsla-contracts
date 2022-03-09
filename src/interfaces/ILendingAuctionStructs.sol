//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface ILendingAuctionStructs {
    //timestamps are uint32, will expire in 2048
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
}
