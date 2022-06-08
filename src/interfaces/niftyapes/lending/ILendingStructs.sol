//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ILendingStructs {
    //timestamps are uint32, will expire in 2048
    struct LoanAuction {
        // SLOT 0 START
        // The original owner of the nft.
        // If there is an active loan on an nft, nifty apes contracts become the holder (original owner)
        // of the underlying nft. This field tracks who to return the nft to if the loan gets repaid.
        address nftOwner;
        // end timestamp of loan
        uint32 loanEndTimestamp;
        /// Last timestamp this loan was updated
        uint32 lastUpdatedTimestamp;
        // Whether or not the loan can be refinanced
        bool fixedTerms;
        // SLOT 1 START
        // The current lender of a loan
        address lender;
        // interest rate of loan in basis points
        uint96 interestRatePerSecond;
        // SLOT 2 START
        // the asset in which the loan has been denominated
        address asset;
        // beginning timestamp of loan
        uint32 loanBeginTimestamp;
        // refinanceByLender was last action, enables slashing
        bool lenderRefi;
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
        // SLOT 5 START
        // This fee is the rate of interest per second for the protocol
        uint96 protocolInterestRatePerSecond;
    }

    /// @dev Struct exists since we ran out of stack space in _repayLoan
    struct RepayLoanStruct {
        uint256 nftId; // 32 bytes
        uint256 paymentAmount; // 32 bytes
        address nftContractAddress; // 20
        bool repayFull; // 1
        bool checkMsgSender; // 1
    }
}
