//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../ErrorReporter.sol";
import "../CarefulMath.sol";

// @dev public interface for LiquidityProviders.sol
interface ILiquidityProviders {
    // Structs

    struct Balance {
        uint256 cAssetBalance;
    }

    // Events

    event NewAssetWhitelisted(address asset, address cAsset);

    event Erc20Supplied(
        address indexed depositor,
        address indexed asset,
        uint256 tokenAmount,
        uint256 cTokenAmount
    );

    // TODO(dankurka): This does not have tokenAmount in here
    event CErc20Supplied(address indexed depositor, address indexed cAsset, uint256 cTokenAmount);

    event Erc20Withdrawn(
        address indexed depositor,
        address indexed asset,
        uint256 tokenAmount,
        uint256 cTokenAmount
    );

    event CErc20Withdrawn(address indexed depositor, address indexed cAsset, uint256 cTokenAmount);

    event EthSupplied(address indexed depositor, uint256 amount, uint256 cTokenAmount);

    event EthWithdrawn(address indexed depositor, uint256 amount, uint256 cTokenAmount);

    // Functions

    function assetToCAsset(address asset) external view returns (address cAsset);

    function setCAssetAddress(address asset, address cAsset) external;

    function getCAssetBalance(address account, address cAsset) external view returns (uint256);

    function supplyErc20(address asset, uint256 numTokensToSupply) external returns (uint256);

    function supplyCErc20(address asset, uint256 numTokensToSupply) external returns (uint256);

    function withdrawErc20(address asset, uint256 amountToWithdraw) external returns (uint256);

    function withdrawCErc20(address asset, uint256 amountToWithdraw) external returns (uint256);

    function supplyEth() external payable returns (uint256);

    function withdrawEth(uint256 amountToWithdraw) external returns (uint256);
}
