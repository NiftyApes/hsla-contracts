// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./Console.sol";
import "ds-test/test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/compound/ICERC20.sol";
import "../interfaces/compound/ICEther.sol";
import "../LiquidityProviders.sol";
import "../Exponential.sol";
import "./Utilities.sol";

// @dev These tests are intended to be run against a forked mainnet.

contract LiquidityProvidersUnitTest is DSTest, TestUtility, Exponential {
    LiquidityProviders liquidityProviders;

    function setUp() public {
        liquidityProviders = new LiquidityProviders();
    }

    function testFoo() public {}
}
