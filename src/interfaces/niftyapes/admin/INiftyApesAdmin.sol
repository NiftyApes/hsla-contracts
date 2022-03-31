//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./INiftyApesAdminEvents.sol";

/// @title NiftyApes interface for the admin role.
interface INiftyApesAdmin is INiftyApesAdminEvents {
    /// @notice Updates the fee that computes protocol interest
    ///         Interest is charged per second on a loan.
    function updateLoanDrawProtocolFeePerSecond(uint96 newLoanDrawProtocolFeePerSecond) external;

    /// @notice Updates the fee for refinancing a loan that the new lender has to pay
    ///         Fees are denomiated in basis points, parts of 10_000
    function updateRefinancePremiumLenderBps(uint16 newPremiumLenderBps) external;

    /// @notice Updates the fee for refinancing a loan that is paid to the protocol
    ///         Fees are denomiated in basis points, parts of 10_000
    function updateRefinancePremiumProtocolBps(uint16 newPremiumProtocolBps) external;

    /// @notice Pauses all interactions with the contract.
    ///         This is intended to be used as an emergency measure to avoid loosing funds.
    function pause() external;

    /// @notice Unpauses all interactions with the contract.
    function unpause() external;
}
