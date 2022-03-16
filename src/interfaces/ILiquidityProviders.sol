//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./ILiquidityProviderEvents.sol";
import "./ILiquidityProviderStructs.sol";

/// @title NiftyApes interface for managing liquidity.
interface ILiquidityProviders is ILiquidityProviderEvents, ILiquidityProviderStructs {
    function assetToCAsset(address asset) external view returns (address cAsset);

    function getCAssetBalance(address account, address cAsset) external view returns (uint256);

    function supplyErc20(address asset, uint256 numTokensToSupply) external returns (uint256);

    function supplyCErc20(address asset, uint256 numTokensToSupply) external;

    function withdrawErc20(address asset, uint256 amountToWithdraw) external returns (uint256);

    function withdrawCErc20(address asset, uint256 amountToWithdraw) external;

    function supplyEth() external payable returns (uint256);

    function withdrawEth(uint256 amountToWithdraw) external returns (uint256);
}
