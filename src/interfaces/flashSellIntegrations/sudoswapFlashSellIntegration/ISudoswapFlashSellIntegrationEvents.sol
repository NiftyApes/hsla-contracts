//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emitted by the SudoswapFlashSellIntegration.
interface ISudoswapFlashSellIntegrationEvents {
    /// @notice Emitted when the associated FlashSell contract address is changed
    /// @param oldFlashSellContractAddress The old FlashSell contract address
    /// @param newFlashSellContractAddress The new FlashSell contract address
    event SudoswapFlashSellIntegrationXFlashSellContractAddressUpdated(
        address oldFlashSellContractAddress,
        address newFlashSellContractAddress
    );

    /// @notice Emitted when the address for Sudoswap Factory contract address is changed
    /// @param newSudoswapFactoryContractAddress The new address of the Sudoswap Factory contract
    event SudoswapFactoryContractAddressUpdated(address newSudoswapFactoryContractAddress);

    /// @notice Emitted when the address for Sudoswap Router contract address is changed
    /// @param newSudoswapRouterContractAddress The new address of the Sudoswap Router contract
    event SudoswapRouterContractAddressUpdated(address newSudoswapRouterContractAddress);
}
