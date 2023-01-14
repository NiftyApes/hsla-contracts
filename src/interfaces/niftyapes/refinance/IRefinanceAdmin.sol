//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IRefinanceEvents.sol";

/// @title NiftyApes Refinance interface for the admin role.
interface IRefinanceAdmin {
    /// @notice Updates the associated liquidity contract address
    function updateLiquidityContractAddress(address newLiquidityContractAddress) external;

    /// @notice Updates the associated offers contract address
    function updateOffersContractAddress(address newOffersContractAddress) external;

    /// @notice Updates the associated lending contract address
    function updateLendingContractAddress(address newLendingContractAddress) external;

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
