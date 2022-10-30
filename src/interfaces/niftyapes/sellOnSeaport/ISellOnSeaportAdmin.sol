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

    /// @notice Updates the OpenseaZone
    function updateOpenseaZone(address newOpenseaZone) external;

    /// @notice Updates the OpenseaFeeRecepient
    function updateOpenseaFeeRecepient(address newOpenseaFeeRecepient) external;

    /// @notice Updates the OpenseaZoneHash
    function updateOpenseaZoneHash(bytes32 newOpenseaZoneHash) external;

    /// @notice Updates the OpenseaConduitKey
    function updateOpenseaConduitKey(bytes32 newOpenseaConduitKey) external;

    /// @notice Updates the OpenseaConduit
    function updateOpenseaConduit(address newOpenseaConduit) external;

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
