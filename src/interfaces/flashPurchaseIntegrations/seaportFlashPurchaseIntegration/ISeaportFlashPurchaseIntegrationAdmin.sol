//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title SeaportFlashPurchaseIntegration interface for the admin role.
interface ISeaportFlashPurchaseIntegrationAdmin {
    /// @notice Updates the associated offers contract address
    function updateOffersContractAddress(address newOffersContractAddress) external;

    /// @notice Updates the associated offers contract address
    function updateFlashPurchaseContractAddress(address newFlashPurchaseContractAddress) external;

    /// @notice Updates the associated seaport contract address
    function updateSeaportContractAddress(address newSeaportContractAddress) external;

    /// @notice Pauses all interactions with the contract.
    ///         This is intended to be used as an emergency measure to avoid loosing funds.
    function pause() external;

    /// @notice Unpauses all interactions with the contract.
    function unpause() external;
}