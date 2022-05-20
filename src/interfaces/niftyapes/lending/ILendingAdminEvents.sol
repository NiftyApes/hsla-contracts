//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emmited for admin changes in the contract.
interface ILendingAdminEvents {
    /// @notice Emmited when the protocol interest fee is updated.
    ///         Interest is charged per second on a loan.
    ///         This is the fee that the protocol charges for facilitating the loan
    /// @param oldProtocolInterestBps The old value denominated in tokens per second
    /// @param newProtocolInterestBps The new value denominated in tokens per second
    event ProtocolInterestBpsUpdated(uint96 oldProtocolInterestBps, uint96 newProtocolInterestBps);

    /// @notice Emmited when the premium that a lender is charged for refinancing a loan is changed
    /// @param oldPremiumLenderBps The old basis points denominated in parts of 10_000
    /// @param newPremiumLenderBps The new basis points denominated in parts of 10_000
    event RefinancePremiumLenderBpsUpdated(uint16 oldPremiumLenderBps, uint16 newPremiumLenderBps);

    /// @notice Emmited when the premium that a lender is charged for refinancing a loan is changed
    /// @param oldPremiumProtocolBps The old basis points denominated in parts of 10_000
    /// @param newPremiumProtocolBps The new basis points denominated in parts of 10_000
    event RefinancePremiumProtocolBpsUpdated(
        uint16 oldPremiumProtocolBps,
        uint16 newPremiumProtocolBps
    );

    /// @notice Emmited when the associated offers contract address is changed
    /// @param oldOffersContractAdress The old offers contract address
    /// @param newOffersContractAdress The new offers contract address
    event OffersContractAddressUpdated(
        address oldOffersContractAdress,
        address newOffersContractAdress
    );

        /// @notice Emmited when the associated liquidity contract address is changed
    /// @param oldLiquidityContractAdress The old liquidity contract address
    /// @param newLiquidityContractAdress The new liquidity contract address
    event LiquidityContractAddressUpdated(
        address oldLiquidityContractAdress,
        address newLiquidityContractAdress
    );
} 