//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ILendingStructs {
    //timestamps are uint32, will expire in 2048
    struct LoanAuction {
        // SLOT 0 START
        // The original owner of the nft.
        // If there is an active loan on an nft, nifty apes contracts become the holder (original owner)
        // of the underlying nft. This field tracks who to return the nft to if the loan gets repaid.
        address nftOwner;
        // loan duration of loan in number of seconds
        uint32 loanEndTimestamp;
        /// Last timestamp this loan was updated
        uint32 lastUpdatedTimestamp;
        // Whether or not the loan can be refinanced
        bool fixedTerms;
        // SLOT 1 START
        // The current lender of a loan
        address lender;
        // This fee is the rate of interest per second
        uint96 interestRatePerSecond;
        // SLOT 2 START
        // TODO(dankurka): replace this field with an enum rather than storing addresses over and over
        // The asset in which the loan has been denominated
        address asset;
        // SLOT 3 START
        // cumulative interest of varying rates paid by new lenders to buy out the loan auction
        uint128 accumulatedLenderInterest;
        // cumulative interest of varying rates accrued by the protocol. To be repaid at the end of the loan.
        uint128 accumulatedProtocolInterest;
        // SLOT 4 START
        // The maximum amount of tokens that can be drawn from this loan
        uint128 amount;
        // amount withdrawn by the nftOwner. This is the amount they will pay interest on, with this value as minimum
        uint128 amountDrawn;
    }

    struct Offer {
        // SLOT 0 START
        // Offer creator
        address creator;
        // offer loan duration
        uint32 duration;
        // The expiration timestamp of the offer in a unix timestamp in seconds
        uint32 expiration;
        // is loan offer fixed terms or open for perpetual auction
        bool fixedTerms;
        // is offer for single NFT or for every NFT in a collection
        bool floorTerm;
        // SLOT 1 START
        // offer NFT contract address
        address nftContractAddress;
        // SLOT 2 START
        // offer NFT ID
        uint256 nftId; // ignored if floorTerm is true
        // SLOT 3 START
        // offer asset type
        address asset;
        // SLOT 4 START
        // offer loan amount
        uint128 amount;
        // offer interest rate in basis points for the loan duration
        uint96 interestRatePerSecond;
    }
}
