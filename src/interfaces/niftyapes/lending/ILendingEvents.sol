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

    /// @notice Emmited when the protocol interest fee is updated.
    ///         Interest is charged per second on a loan.
    ///         This is the fee that the protocol charges for facilitating the loan
    /// @param oldProtocolInterestBps The old value denominated in tokens per second
    /// @param newProtocolInterestBps The new value denominated in tokens per second
    event ProtocolInterestBpsUpdated(uint96 oldProtocolInterestBps, uint96 newProtocolInterestBps);

    /// @notice Emmited when the the bps premium for refinancing a loan that the new lender has to pay is changed
    /// @param oldOriginationPremiumBps The old basis points denominated in parts of 10_000
    /// @param newOriginationPremiumBps The new basis points denominated in parts of 10_000
    event OriginationPremiumBpsUpdated(
        uint16 oldOriginationPremiumBps,
        uint16 newOriginationPremiumBps
    );

    /// @notice Emmited when the bps premium for refinancing a loan before the current lender has earned the equivalent amount of interest has changed
    /// @param oldGasGriefingPremiumBps The old basis points denominated in parts of 10_000
    /// @param newGasGriefingPremiumBps The new basis points denominated in parts of 10_000
    event GasGriefingPremiumBpsUpdated(
        uint16 oldGasGriefingPremiumBps,
        uint16 newGasGriefingPremiumBps
    );

    /// @notice Emmited when the bps premium paid to the protocol for refinancing a loan before the current lender has earned the equivalent amount of interest is changed
    /// @param oldGasGriefingProtocolPremiumBps The old basis points denominated in parts of 10_000
    /// @param newGasGriefingProtocolPremiumBps The new basis points denominated in parts of 10_000
    event GasGriefingProtocolPremiumBpsUpdated(
        uint16 oldGasGriefingProtocolPremiumBps,
        uint16 newGasGriefingProtocolPremiumBps
    );

    /// @notice Emmited when the bps premium paid to the protocol for refinancing a loan with terms that do not improve the cumulative terms of the loan by the equivalant basis points is changed
    /// @param oldTermGriefingPremiumBps The old basis points denominated in parts of 10_000
    /// @param newTermGriefingPremiumBps The new basis points denominated in parts of 10_000
    event TermGriefingPremiumBpsUpdated(
        uint16 oldTermGriefingPremiumBps,
        uint16 newTermGriefingPremiumBps
    );

    /// @notice Emmited when the bps premium paid to the protocol for refinancing a loan within 1 hour of default is changed
    /// @param oldDefaultRefinancePremiumBps The old basis points denominated in parts of 10_000
    /// @param newDefaultRefinancePremiumBps The new basis points denominated in parts of 10_000
    event DefaultRefinancePremiumBpsUpdated(
        uint16 oldDefaultRefinancePremiumBps,
        uint16 newDefaultRefinancePremiumBps
    );

    /// @notice Emmited when the associated offers contract address is changed
    /// @param oldOffersContractAdress The old offers contract address
    /// @param newOffersContractAdress The new offers contract address
    event LendingXOffersContractAddressUpdated(
        address oldOffersContractAdress,
        address newOffersContractAdress
    );

    /// @notice Emmited when the associated liquidity contract address is changed
    /// @param oldLiquidityContractAdress The old liquidity contract address
    /// @param newLiquidityContractAdress The new liquidity contract address
    event LendingXLiquidityContractAddressUpdated(
        address oldLiquidityContractAdress,
        address newLiquidityContractAdress
    );

    /// @notice Emmited when the associated signature lending contract address is changed
    /// @param oldSigLendingContractAdress The old liquidity contract address
    /// @param newSigLendingContractAdress The new liquidity contract address
    event LendingXSigLendingContractAddressUpdated(
        address oldSigLendingContractAdress,
        address newSigLendingContractAdress
    );

    /// @notice Emmited when sanctions checks are paused
    event LendingSanctionsPaused();

    /// @notice Emmited when sanctions checks are unpaused
    event LendingSanctionsUnpaused();
}
