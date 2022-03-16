//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface ILiquidityEvents {
    event NewAssetWhitelisted(address asset, address cAsset);

    event Erc20Supplied(
        address indexed depositor,
        address indexed asset,
        uint256 tokenAmount,
        uint256 cTokenAmount
    );

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
}
