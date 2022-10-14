//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emitted by the SudoswapPwfIntegration.
interface ISudoswapPwfIntegrationEvents {
    /// @notice Emitted when the associated offers contract address is changed
    /// @param oldOffersContractAddress The old offers contract address
    /// @param newOffersContractAddress The new offers contract address
    event SudoswapPwfIntegrationXOffersContractAddressUpdated(
        address oldOffersContractAddress,
        address newOffersContractAddress
    );

    /// @notice Emitted when the associated PurchaseWithFinancing contract address is changed
    /// @param oldPurchaseWithFinancingContractAddress The old PurchaseWithFinancing contract address
    /// @param newPurchaseWithFinancingContractAddress The new PurchaseWithFinancing contract address
    event SudoswapPwfIntegrationXPurchaseWithFinancingContractAddressUpdated(
        address oldPurchaseWithFinancingContractAddress,
        address newPurchaseWithFinancingContractAddress
    );

    /// @notice Emitted when the address for Sudoswap Factory contract address is changed
    /// @param newSudoswapFactoryContractAddress The new address of the Sudoswap Factory contract
    event SudoswapFactoryContractAddressUpdated(address newSudoswapFactoryContractAddress);

    /// @notice Emitted when the address for Sudoswap Router contract address is changed
    /// @param newSudoswapRouterContractAddress The new address of the Sudoswap Router contract
    event SudoswapRouterContractAddressUpdated(address newSudoswapRouterContractAddress);
}
