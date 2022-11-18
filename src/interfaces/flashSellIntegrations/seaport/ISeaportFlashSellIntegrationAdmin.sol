//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title SeaportFlashSellIntegration interface for the admin role.
interface ISeaportFlashSellIntegrationAdmin {
    /// @notice Updates the associated flashSell contract address
    function updateFlashSellContractAddress(address newFlashSellContractAddress) external;

    /// @notice Updates the weth contract address
    function updateWethContractAddress(address newWethContractAddress) external;

    /// @notice Updates the associated seaport contract address
    function updateSeaportContractAddress(address newSeaportContractAddress) external;

    /// @notice Pauses all interactions with the contract.
    ///         This is intended to be used as an emergency measure to avoid loosing funds.
    function pause() external;

    /// @notice Unpauses all interactions with the contract.
    function unpause() external;
}
