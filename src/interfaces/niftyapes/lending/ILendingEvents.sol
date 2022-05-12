//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../offers/IOffersStructs.sol";

/// @title Events emmited by the lending part of the protocol.
interface ILendingEvents {
    /// @notice Emmited when a new loan is executed
    /// @param lender The lender of the loan
    /// @param asset The asset in which the offer is denominated
    /// @param borrower The borrower of the loan
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    /// @param offer The offer details
    event LoanExecuted(
        address indexed lender,
        address asset,
        address borrower,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        IOffersStructs.Offer offer
    );

    /// @notice Emited when a loan is refinanced
    /// @param lender The lender of the loan
    /// @param asset The asset in which the offer is denominated
    /// @param borrower The borrower of the loan
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    /// @param offer The offer details
    event Refinance(
        address indexed lender,
        address asset,
        address borrower,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        IOffersStructs.Offer offer
    );

    /// @notice Emitted when a loan amount is drawn
    /// @param borrower The borrower of the loan
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    /// @param drawAmount The added amount drawn
    ///  @param totalDrawn The total amount drawn now
    event AmountDrawn(
        address indexed borrower,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        uint256 drawAmount,
        uint256 totalDrawn
    );

    /// @notice Emitted when a loan is repaid
    /// @param lender The lender of the loan
    /// @param borrower The borrower of the loan
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    /// @param asset The asset of the loan
    ///  @param totalPayment The total payment amount
    event LoanRepaid(
        address indexed lender,
        address borrower,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address asset,
        uint256 totalPayment
    );

    /// @notice Emitted when a loan is partially repaid
    /// @param lender The lender of the loan
    /// @param borrower The borrower of the loan
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    /// @param asset The asset of the loan
    ///  @param amount The payment amount
    event PartialRepayment(
        address indexed lender,
        address borrower,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address asset,
        uint256 amount
    );

    /// @notice Emitted when an asset is seized
    /// @param lender The lender of the loan
    /// @param borrower The borrower of the loan
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    event AssetSeized(
        address indexed lender,
        address borrower,
        address indexed nftContractAddress,
        uint256 indexed nftId
    );
}
