//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emmited for admin changes in the contract.
interface ILiquidityAdminEvents {
    /// @notice Emmited when a new addest and its corresponding asset are added to nifty apes allow list
    /// @param asset The asset being added to the allow list
    /// @param cAsset The address of the corresponding compound token
    event NewAssetListed(address asset, address cAsset);

    /// @notice Emmited when the bps of reveneue sent to the Regen Collective is changed
    /// @param oldRegenCollectiveBpsOfRevenue The old basis points denominated in parts of 10_000
    /// @param newRegenCollectiveBpsOfRevenue The new basis points denominated in parts of 10_000
    event RegenCollectiveBpsOfRevenueUpdated(
        uint16 oldRegenCollectiveBpsOfRevenue,
        uint16 newRegenCollectiveBpsOfRevenue
    );

    /// @notice Emmited when the address for the Regen Collective is changed
    /// @param newRegenCollectiveAddress The new address of the Regen Collective
    event RegenCollectiveAddressUpdated(
        address newRegenCollectiveAddress
    ); 
} 