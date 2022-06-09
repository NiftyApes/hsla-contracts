//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ILendingEvents.sol";

/// @title NiftyApes interface for the admin role.
interface ILendingAdmin {
    /// @notice Updates the fee that computes protocol interest due on loan payback
    ///         Interest is charged per second on a loan.
    function updateProtocolInterestBps(uint96 newProtocolInterestBps) external;

    /// @notice Updates the bps premium for refinancing a loan that the new lender has to pay
    ///         Fees are denomiated in basis points, parts of 10_000
    function updateOriginationPremiumLenderBps(uint16 newOriginationPremiumBps) external;

    /// @notice Updates the bps premium for refinancing a loan before the current lender has earned the equivalent amount of interest
    ///         Fees are denomiated in basis points, parts of 10_000
    function updateGasGriefingPremiumBps(uint16 newGasGriefingPremiumBps) external;

    /// @notice Updates the bps premium paid to the protocol for refinancing a loan before the current lender has earned the equivalent amount of interest
    ///         Fees are denomiated in basis points, parts of 10_000
    function updateGasGriefingProtocolPremiumBps(uint16 newGasGriefingProtocolPremiumBps) external;

    /// @notice Updates the bps premium paid to the protocol for refinancing a loan with terms that do not improve the cumulative terms of the loan by the equivalant basis points
    ///         Fees are denomiated in basis points, parts of 10_000
    function updateTermGriefingPremiumBps(uint16 newTermGriefingPremiumBps) external;

    /// @notice Updates the bps premium paid to the protocol for refinancing a loan within 1 hour of default
    ///         Fees are denomiated in basis points, parts of 10_000
    function updateDefaultRefinancePremiumBps(uint16 newDefaultRefinancePremiumBps) external;

    /// @notice Updates the associated offers contract address
    function updateOffersContractAddress(address newOffersContractAddress) external;

    /// @notice Updates the associated liquidity contract address
    function updateLiquidityContractAddress(address newLiquidityContractAddress) external;

    /// @notice Updates the associated signature lending contract address
    function updateSigLendingContractAddress(address newSigLendingContractAddress) external;

    /// @notice Pauses sanctions checks
    function pauseSanctions() external;

    /// @notice Unpauses sanctions checks
    function unpauseSanctions() external;

    /// @notice Pauses all interactions with the contract.
    ///         This is intended to be used as an emergency measure to avoid loosing funds.
    function pause() external;

    /// @notice Unpauses all interactions with the contract.
    function unpause() external;
}
