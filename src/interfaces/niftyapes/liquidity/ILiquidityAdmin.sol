//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ILiquidityAdminEvents.sol";

/// @title NiftyApes interface for the admin role.
interface ILiquidityAdmin is INiftyApesAdminEvents {
    /// @notice Allows the owner of the contract to add an asset to the allow list
    ///         All assets on NiftyApes have to have a mapping present from asset to cAsset,
    ///         The asset is a token like USDC while the cAsset is the corresponding token in compound cUSDC.
    function setCAssetAddress(address asset, address cAsset) external;

    /// @notice Updates the maximum cAsset balance that the contracts will allow
    ///         This allows a guarded launch with NiftyApes limiting the amount of liquidity
    ///         in the protocol.
    function setMaxCAssetBalance(address asset, uint256 maxBalance) external;

    /// @notice Pauses all interactions with the contract.
    ///         This is intended to be used as an emergency measure to avoid loosing funds.
    function pause() external;

    /// @notice Unpauses all interactions with the contract.
    function unpause() external;
}
