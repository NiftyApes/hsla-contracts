//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emitted by the SudoswapFlashPurchaseIntegration.
interface ISudoswapFlashPurchaseIntegrationEvents {
    /// @notice Emitted when the associated offers contract address is changed
    /// @param oldOffersContractAddress The old offers contract address
    /// @param newOffersContractAddress The new offers contract address
    event SudoswapFlashPurchaseIntegrationXOffersContractAddressUpdated(
        address oldOffersContractAddress,
        address newOffersContractAddress
    );

    /// @notice Emitted when the associated FlashPurchase contract address is changed
    /// @param oldFlashPurchaseContractAddress The old FlashPurchase contract address
    /// @param newFlashPurchaseContractAddress The new FlashPurchase contract address
    event SudoswapFlashPurchaseIntegrationXFlashPurchaseContractAddressUpdated(
        address oldFlashPurchaseContractAddress,
        address newFlashPurchaseContractAddress
    );

    /// @notice Emitted when the address for Sudoswap Factory contract address is changed
    /// @param newSudoswapFactoryContractAddress The new address of the Sudoswap Factory contract
    event SudoswapFactoryContractAddressUpdated(address newSudoswapFactoryContractAddress);

    /// @notice Emitted when the address for Sudoswap Router contract address is changed
    /// @param newSudoswapRouterContractAddress The new address of the Sudoswap Router contract
    event SudoswapRouterContractAddressUpdated(address newSudoswapRouterContractAddress);
}
