//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

/// @title NiftyApes interface for the admin role.
interface INiftyApesAdmin {
    /// @notice Allows the owner of the contract to add an asset to the allow list
    ///         All assets on NiftyApes have to have a mapping present from asset to cAsset,
    ///         The asset is a token like USDC while the cAsset is the corresponding token in compound cUSDC.
    function setCAssetAddress(address asset, address cAsset) external;

    /// @notice Updates the maximum cAsset balance that the contracts will allow
    ///         This allows a guarded launch with NiftyApes limiting the amount of liquidity
    ///         in the protocol.
    function setMaxCAssetBalance(address asset, uint256 maxBalance) external;

    /// @notice Updates the fee that computes protocol interest
    ///         Fees are denomiated in basis points, parts of 10_000
    // TODO(dankurka): wrong
    function updateLoanDrawProtocolFeePerSecond(uint128 newLoanDrawProtocolFeePerSecond) external;

    /// @notice Updates the fee for refinancing a loan that the new lender has to pay
    ///         Fees are denomiated in basis points, parts of 10_000
    function updateRefinancePremiumLenderFee(uint16 newPremiumLenderBps) external;

    /// @notice Updates the fee for refinancing a loan that is paid to the protocol
    ///         Fees are denomiated in basis points, parts of 10_000
    function updateRefinancePremiumProtocolFee(uint16 newPremiumProtocolBps) external;

    /// @notice Pauses all interactions with the contract.
    ///         This is intended to be used as an emergency measure to avoid loosing funds.
    function pause() external;

    /// @notice Unpauses all interactions with the contract.
    function unpause() external;
}
