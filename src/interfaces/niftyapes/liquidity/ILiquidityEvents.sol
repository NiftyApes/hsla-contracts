//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title Events emmited for changes in liquidity
interface ILiquidityEvents {
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
