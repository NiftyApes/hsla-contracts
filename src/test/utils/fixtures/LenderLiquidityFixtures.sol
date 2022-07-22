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
            defaultUsdcLiquiditySupplied = usdcToken.balanceOf(lender1);
        } else {
            defaultUsdcLiquiditySupplied = 3672711471 * uint128(10**usdcToken.decimals());
        }

        vm.startPrank(lender1);
        liquidity.supplyEth{ value: defaultEthLiquiditySupplied }();
        usdcToken.approve(address(liquidity), usdcToken.balanceOf(lender1));
        liquidity.supplyErc20(address(usdcToken), defaultUsdcLiquiditySupplied);
        vm.stopPrank();

        vm.startPrank(lender2);
        liquidity.supplyEth{ value: defaultEthLiquiditySupplied }();
        usdcToken.approve(address(liquidity), usdcToken.balanceOf(lender2));
        liquidity.supplyErc20(address(usdcToken), defaultUsdcLiquiditySupplied);
        vm.stopPrank();

        vm.startPrank(lender3);
        liquidity.supplyEth{ value: defaultEthLiquiditySupplied }();
        usdcToken.approve(address(liquidity), defaultUsdcLiquiditySupplied);
        liquidity.supplyErc20(address(usdcToken), defaultUsdcLiquiditySupplied);
        vm.stopPrank();
    }

    function resetSuppliedUsdcLiquidity(address lender, uint256 amount) internal {
        vm.startPrank(lender);
        liquidity.withdrawErc20(
            address(usdcToken),
            liquidity.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidity.getCAssetBalance(lender, address(cUSDCToken))
            )
        );
        usdcToken.approve(address(liquidity), amount);
        liquidity.supplyErc20(address(usdcToken), amount);
        vm.stopPrank();
    }

    function resetSuppliedEthLiquidity(address lender, uint256 amount) internal {
        vm.startPrank(lender);
        liquidity.withdrawEth(
            liquidity.cAssetAmountToAssetAmount(
                address(cEtherToken),
                liquidity.getCAssetBalance(lender, address(cEtherToken))
            )
        );
        liquidity.supplyEth{ value: amount }();
        vm.stopPrank();
    }
}
