// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "./NiftyApesDeployment.sol";

contract LenderLiquidityFixtures is Test, NiftyApesDeployment {
    uint256 internal defaultEthLiquiditySupplied = 1000 ether;
    uint256 internal defaultUsdcLiquiditySupplied;

    function setUp() public virtual override {
        super.setUp();

        defaultUsdcLiquiditySupplied = 1000 * (10**usdcToken.decimals());

        vm.startPrank(lender1);
        liquidity.supplyEth{ value: defaultEthLiquiditySupplied }();
        usdcToken.approve(address(liquidity), defaultUsdcLiquiditySupplied);
        liquidity.supplyErc20(address(usdcToken), defaultUsdcLiquiditySupplied);
        vm.stopPrank();

        vm.startPrank(lender2);
        liquidity.supplyEth{ value: defaultEthLiquiditySupplied }();
        usdcToken.approve(address(liquidity), defaultUsdcLiquiditySupplied);
        liquidity.supplyErc20(address(usdcToken), defaultUsdcLiquiditySupplied);
        vm.stopPrank();
    }
}
