//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emitted by the SeaportFlashPurchaseIntegration.
interface ISeaportFlashPurchaseIntegrationEvents {
    /// @notice Emitted when the associated offers contract address is changed
    /// @param oldOffersContractAddress The old offers contract address
    /// @param newOffersContractAddress The new offers contract address
    event SeaportFlashPurchaseIntegrationXOffersContractAddressUpdated(
        address oldOffersContractAddress,
        address newOffersContractAddress
    );

    /// @notice Emitted when the associated FlashPurchase contract address is changed
    /// @param oldFlashPurchaseContractAddress The old FlashPurchase contract address
    /// @param newFlashPurchaseContractAddress The new FlashPurchase contract address
    event SeaportFlashPurchaseIntegrationXFlashPurchaseContractAddressUpdated(
        address oldFlashPurchaseContractAddress,
        address newFlashPurchaseContractAddress
    );

    /// @notice Emitted when the address for Seaport is changed
    /// @param newSeaportContractAddress The new address of the Seaport Contract
    event SeaportContractAddressUpdated(address newSeaportContractAddress);
}
