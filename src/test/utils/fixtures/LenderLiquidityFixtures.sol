// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "./NiftyApesDeployment.sol";

contract LenderLiquidityFixtures is Test, NiftyApesDeployment {
    uint256 internal defaultLiquiditySupplied = 1000 ether;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(lender1);
        liquidity.supplyEth{ value: defaultLiquiditySupplied }();
        usdcToken.approve(address(liquidity), defaultLiquiditySupplied);
        liquidity.supplyErc20(address(usdcToken), defaultLiquiditySupplied);
        vm.stopPrank();

        vm.startPrank(lender2);
        liquidity.supplyEth{ value: defaultLiquiditySupplied }();
        usdcToken.approve(address(liquidity), defaultLiquiditySupplied);
        liquidity.supplyErc20(address(usdcToken), defaultLiquiditySupplied);
        vm.stopPrank();
    }
}
