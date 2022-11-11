//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title SellOnSeaport interface for the admin role.
interface ISellOnSeaportAdmin {
    /// @notice Updates the associated liquidity contract address
    function updateLiquidityContractAddress(address newLiquidityContractAddress) external;

    /// @notice Updates the associated lending contract address
    function updateLendingContractAddress(address newLendingContractAddress) external;

    /// @notice Updates the associated seaport contract address
    function updateSeaportContractAddress(address newSeaportContractAddress) external;

    /// @notice Updates the OpenSeaZone
    function updateOpenSeaZone(address newOpenSeaZone) external;

    /// @notice Updates the OpenSeaFeeRecepient
    function updateOpenSeaFeeRecepient(address newOpenSeaFeeRecepient) external;

    /// @notice Updates the OpenSeaZoneHash
    function updateOpenSeaZoneHash(bytes32 newOpenSeaZoneHash) external;

    /// @notice Updates the OpenSeaConduitKey
    function updateOpenSeaConduitKey(bytes32 newOpenSeaConduitKey) external;

    /// @notice Updates the OpenSeaConduit
    function updateOpenSeaConduit(address newOpenSeaConduit) external;

    /// @notice Pauses sanctions checks
    function pauseSanctions() external;

    /// @notice Unpauses sanctions checks
    function unpauseSanctions() external;

    /// @notice Pauses all interactions with the contract.
    ///         This is intended to be used as an emergency measure to avoid loosing funds.
    function pause() external;

    /// @notice Unpauses all interactions with the contract.
    function unpause() external;
}
