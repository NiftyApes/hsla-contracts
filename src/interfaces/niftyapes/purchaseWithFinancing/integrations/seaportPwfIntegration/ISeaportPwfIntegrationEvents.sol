//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emitted by the SeaportPwfIntegration.
interface ISeaportPwfIntegrationEvents {
    /// @notice Emitted when the associated offers contract address is changed
    /// @param oldOffersContractAddress The old offers contract address
    /// @param newOffersContractAddress The new offers contract address
    event SeaportPwfIntegrationXOffersContractAddressUpdated(
        address oldOffersContractAddress,
        address newOffersContractAddress
    );

    /// @notice Emitted when the associated PurchaseWithFinancing contract address is changed
    /// @param oldPurchaseWithFinancingContractAddress The old PurchaseWithFinancing contract address
    /// @param newPurchaseWithFinancingContractAddress The new PurchaseWithFinancing contract address
    event SeaportPwfIntegrationXPurchaseWithFinancingContractAddressUpdated(
        address oldPurchaseWithFinancingContractAddress,
        address newPurchaseWithFinancingContractAddress
    );

    /// @notice Emitted when the address for Seaport is changed
    /// @param newSeaportContractAddress The new address of the Seaport Contract
    event SeaportContractAddressUpdated(address newSeaportContractAddress);
}
