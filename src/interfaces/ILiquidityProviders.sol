//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../ErrorReporter.sol";
import "../CarefulMath.sol";

// @dev public interface for LiquidityProviders.sol
interface ILiquidityProviders {
    // Structs

    struct AccountAssets {
        address[] keys;
        mapping(address => uint256) cAssetBalance;
        mapping(address => uint256) utilizedCAssetBalance;
        mapping(address => uint256) indexOf;
        mapping(address => bool) inserted;
    }

    // Events

    event newAssetWhitelisted(address asset, address cAsset);

    event Erc20Supplied(address depositor, address asset, uint256 amount);

    event CErc20Supplied(address depositor, address asset, uint256 amount);

    event Erc20Withdrawn(
        address depositor,
        address asset,
        uint256 amount
    );

    event CErc20Withdrawn(address depositor, address asset, uint256 amount);

    event EthSupplied(address depositor, uint256 amount);

    event CEthSupplied(address depositor, uint256 amount);

    event EthWithdrawn(address depositor, uint256 amount);

    event CEthWithdrawn(address depositor, uint256 amount);

    // Functions

    function assetToCAsset(address asset)
        external
        view
        returns (address cAsset);

    function setCAssetAddress(address asset, address cAsset) external;

    function getAssetsIn(address depositor)
        external
        view
        returns (address[] memory assetsIn);

    function getCAssetBalances(address account, address cAsset)
        external
        view
        returns (
            uint256 cAssetBalance,
            uint256 utilizedCAssetBalance,
            uint256 availableCAssetBalance
        );

    function getAvailableCAssetBalance(address account, address cAsset)
        external
        view
        returns (uint256 availableCAssetBalance);

    function getCAssetBalancesAtIndex(address account, uint256 index)
        external
        view
        returns (
            uint256 cAssetBalance,
            uint256 utilizedCAssetBalance,
            uint256 availableCAssetBalance
        );

    function accountAssetsSize(address account)
        external
        view
        returns (uint256 numberOfAccountAssets);

    function supplyErc20(address asset, uint256 numTokensToSupply)
        external
        returns (uint256);

    function supplyCErc20(address asset, uint256 numTokensToSupply)
        external
        returns (uint256);

    function withdrawErc20(address asset, uint256 amountToWithdraw)
        external
        returns (uint256);

    function withdrawCErc20(address asset, uint256 amountToWithdraw)
        external
        returns (uint256);

    function supplyEth() external payable returns (uint256);

    function supplyCEth(uint256 numTokensToSupply) external returns (uint256);

    function withdrawEth(uint256 amountToWithdraw) external returns (uint256);

    function withdrawCEth(uint256 amountToWithdraw) external returns (uint256);
}
