//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emitted by the SeaportFlashSellIntegration.
interface ISeaportFlashSellIntegrationEvents {
    /// @notice Emitted when the associated FlashSell contract address is changed
    /// @param oldFlashSellContractAddress The old FlashSell contract address
    /// @param newFlashSellContractAddress The new FlashSell contract address
    event SeaportFlashSellIntegrationXFlashSellContractAddressUpdated(
        address oldFlashSellContractAddress,
        address newFlashSellContractAddress
    );

    /// @notice Emitted when the weth contract address is changed
    /// @param oldWethContractAddress The old weth contract address
    /// @param newWethContractAddress The new weth contract address
    event SeaportFlashSellIntegrationXWethContractAddressUpdated(
        address oldWethContractAddress,
        address newWethContractAddress
    );

    /// @notice Emitted when the address for Seaport is changed
    /// @param oldSeaportContractAddress The old address of the Seaport Contract
    /// @param newSeaportContractAddress The new address of the Seaport Contract
    event SeaportFlashSellIntegrationXSeaportContractAddressUpdated(
        address oldSeaportContractAddress,
        address newSeaportContractAddress
    );
}
