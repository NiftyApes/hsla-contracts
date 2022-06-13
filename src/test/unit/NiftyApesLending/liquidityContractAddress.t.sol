// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../common/BaseTest.sol";
import "../../../Lending.sol";
import "../../../Liquidity.sol";

import "forge-std/Test.sol";

contract TestLiquidityContractAddress is BaseTest {
    NiftyApesLending private lendingContract;
    NiftyApesLiquidity private liquidityContract;

    function setUp() public {
        lendingContract = new NiftyApesLending();
        lendingContract.initialize();

        liquidityContract = new NiftyApesLiquidity();
        liquidityContract.initialize();
        lendingContract.updateLiquidityContractAddress(address(liquidityContract));
    }

    function testLiquidityContractAddress_works() public {
        assertEq(lendingContract.liquidityContractAddress(), address(liquidityContract));
    }

    function testLiquidityContractAddress_after_update() public {
        NiftyApesLiquidity newLiquidityContract = new NiftyApesLiquidity();
        assertTrue(address(liquidityContract) != address(newLiquidityContract));

        newLiquidityContract.initialize();

        assertEq(lendingContract.liquidityContractAddress(), address(liquidityContract));
        lendingContract.updateLiquidityContractAddress(address(newLiquidityContract));
        assertEq(lendingContract.liquidityContractAddress(), address(newLiquidityContract));
    }
}
