// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "./NiftyApesDeployment.sol";

contract LenderLiquidityFixtures is Test, NiftyApesDeployment {
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(lender1);
        liquidity.supplyEth{ value: 1000 ether }();
        usdcToken.approve(address(liquidity), 1000 ether);
        liquidity.supplyErc20(address(usdcToken), 1000 ether);
        vm.stopPrank();

        vm.startPrank(lender2);
        liquidity.supplyEth{ value: 1000 ether }();
        usdcToken.approve(address(liquidity), 1000 ether);
        liquidity.supplyErc20(address(usdcToken), 1000 ether);
        vm.stopPrank();
    }
}
