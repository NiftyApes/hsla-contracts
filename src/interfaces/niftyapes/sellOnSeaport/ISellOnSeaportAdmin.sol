//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title SellOnSeaport interface for the admin role.
interface ISellOnSeaportAdmin {
    /// @notice Updates the associated liquidity contract address
    function updateLiquidityContractAddress(address newLiquidityContractAddress) external;

    /// @notice Updates the associated lending contract address
    function updateLendingContractAddress(address newLendingContractAddress) external;

    /// @notice Updates the associated flashSell contract address
    function updateFlashSellContractAddress(address newFlashSellContractAddress) external;

    /// @notice Updates the associated weth contract address
    function updateWethContractAddress(address newWethContractAddress) external;

    /// @notice Updates the associated seaport contract address
    function updateSeaportContractAddress(address newSeaportContractAddress) external;

    /// @notice Updates the SeaportZone
    function updateSeaportZone(address newSeaportZone) external;

    /// @notice Updates the SeaportFeeRecepient
    function updateSeaportFeeRecepient(address newSeaportFeeRecepient) external;

    /// @notice Updates the SeaportZoneHash
    function updateSeaportZoneHash(bytes32 newSeaportZoneHash) external;

    /// @notice Updates the SeaportConduitKey
    function updateSeaportConduitKey(bytes32 newSeaportConduitKey) external;

    /// @notice Updates the SeaportConduit
    function updateSeaportConduit(address newSeaportConduit) external;

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
