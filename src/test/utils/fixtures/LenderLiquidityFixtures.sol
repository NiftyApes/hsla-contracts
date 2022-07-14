// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "./NiftyApesDeployment.sol";

contract LenderLiquidityFixtures is Test, NiftyApesDeployment {
    uint256 internal defaultEthLiquiditySupplied = address(lender1).balance;
    uint256 internal defaultUsdcLiquiditySupplied;

    function setUp() public virtual override {
        super.setUp();

        if (integration) {
            defaultUsdcLiquiditySupplied = 3672711471 * uint128(10**usdcToken.decimals());
        } else {
            defaultUsdcLiquiditySupplied = 3672711471 * uint128(10**usdcToken.decimals());
        }

        vm.startPrank(lender1);
        liquidity.supplyEth{ value: defaultEthLiquiditySupplied }();
        usdcToken.approve(address(liquidity), usdcToken.balanceOf(lender1));
        liquidity.supplyErc20(address(usdcToken), usdcToken.balanceOf(lender1));
        vm.stopPrank();

        vm.startPrank(lender2);
        liquidity.supplyEth{ value: defaultEthLiquiditySupplied }();
        usdcToken.approve(address(liquidity), usdcToken.balanceOf(lender2));
        liquidity.supplyErc20(address(usdcToken), usdcToken.balanceOf(lender2));
        vm.stopPrank();
    }
}
