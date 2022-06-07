//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ILendingEvents.sol";

/// @title NiftyApes interface for the admin role.
interface ILendingAdmin {
    /// @notice Updates the associated offers contract address
    function updateOffersContractAddress(address newOffersContractAddress) external;

    /// @notice Updates the associated liquidity contract address
    function updateLendingContractAddress(address newLendingContractAddress) external;

    /// @notice Pauses all interactions with the contract.
    ///         This is intended to be used as an emergency measure to avoid loosing funds.
    function pause() external;

    /// @notice Unpauses all interactions with the contract.
    function unpause() external;
}
