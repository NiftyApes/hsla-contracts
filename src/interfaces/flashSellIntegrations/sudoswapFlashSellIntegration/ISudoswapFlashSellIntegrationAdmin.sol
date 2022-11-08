//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title SudoswapFlashSellIntegration interface for the admin role.
interface ISudoswapFlashSellIntegrationAdmin {
    /// @notice Updates the associated offers contract address
    function updateFlashSellContractAddress(address newFlashSellContractAddress) external;

    /// @notice Updates the associated sudoswap factory contract address
    function updateSudoswapFactoryContractAddress(address newSudoswapFactoryContractAddress) external;

    /// @notice Updates the associated sudoswap router contract address
    function updateSudoswapRouterContractAddress(address newSudoswapRouterContractAddress) external;

    /// @notice Pauses all interactions with the contract.
    ///         This is intended to be used as an emergency measure to avoid loosing funds.
    function pause() external;

    /// @notice Unpauses all interactions with the contract.
    function unpause() external;
}
