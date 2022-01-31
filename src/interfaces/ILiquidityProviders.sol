//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../ErrorReporter.sol";
import "../CarefulMath.sol";

// @dev public interface for LiquidityProviders.sol
interface ILiquidityProviders {
    // Structs

    struct MintLocalVars {
        ComptrollerErrorReporter.Error err;
        CarefulMath.MathError mathErr;
        uint256 exchangeRateMantissa;
        uint256 mintTokens;
        uint256 totalSupplyNew;
        uint256 accountTokensNew;
        uint256 mintAmount;
    }

    struct RedeemLocalVars {
        ComptrollerErrorReporter.Error err;
        CarefulMath.MathError mathErr;
        uint256 exchangeRateMantissa;
        uint256 redeemTokens;
        uint256 redeemAmount;
        uint256 totalSupplyNew;
        uint256 accountTokensNew;
    }

    // Events

    event newAssetWhitelisted(address asset, address cAsset);

    event Erc20Supplied(address depositor, address asset, uint256 amount);

    event CErc20Supplied(address depositor, address asset, uint256 amount);

    event Erc20Withdrawn(
        address depositor,
        address asset,
        bool redeemType,
        uint256 amount
    );

    event CErc20Withdrawn(address depositor, address asset, uint256 amount);

    event EthSupplied(address depositor, uint256 amount);

    event CEthSupplied(address depositor, uint256 amount);

    event EthWithdrawn(address depositor, bool redeemType, uint256 amount);

    event CEthWithdrawn(address depositor, uint256 amount);

    // Functions

    function assetToCAsset(address asset)
        external
        view
        returns (address cAsset);

    function cAssetBalances(address cAsset, address depositor)
        external
        view
        returns (uint256 balance);

    function utilizedCAssetBalances(address cAsset, address depositor)
        external
        view
        returns (uint256 balance);

    function getAssetsIn(address depositor)
        external
        view
        returns (address[] memory enteredMarkets);

    function setCAssetAddress(address asset, address cAsset) external;

    function supplyErc20(address asset, uint256 numTokensToSupply)
        external
        returns (uint256);

    function supplyCErc20(address asset, uint256 numTokensToSupply)
        external
        returns (uint256);

    function withdrawErc20(
        address asset,
        bool redeemType,
        uint256 amountToWithdraw
    ) external returns (uint256);

    function withdrawCErc20(address asset, uint256 amountToWithdraw)
        external
        returns (uint256);

    function supplyEth() external payable returns (uint256);

    function supplyCEth(uint256 numTokensToSupply) external returns (uint256);

    function withdrawEth(bool redeemType, uint256 amountToWithdraw)
        external
        returns (uint256);

    function withdrawCEth(uint256 amountToWithdraw) external returns (uint256);
}
