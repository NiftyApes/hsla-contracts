// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../Liquidity.sol";
import "../../../Lending.sol";
import "../../common/BaseTest.sol";

import "forge-std/Test.sol";

contract TestUpdateLiquidityContractAddress is BaseTest, Test {
    NiftyApesLending private lendingContract;
    NiftyApesLiquidity private liquidityContract;

    // Below are two random addresses
    address private constant EOA_1 = 0x503408564C50b43208529faEf9bdf9794c015d52;
    address private constant EOA_2 = 0x4a3A70D6Be2290f5F57Ac7E64b9A1B7695f5b0B3;

    function setUp() public {
        vm.startPrank(EOA_1);

        lendingContract = new NiftyApesLending();
        lendingContract.initialize();
        liquidityContract = new NiftyApesLiquidity();
        liquidityContract.initialize();
        lendingContract.updateLiquidityContractAddress(address(liquidityContract));

        vm.stopPrank();
    }

    function testUpdateLiquidityContractAddress_works() public {
        NiftyApesLiquidity newLiquidityContract = new NiftyApesLiquidity();
        newLiquidityContract.initialize();

        vm.prank(EOA_1);
        lendingContract.updateLiquidityContractAddress(address(newLiquidityContract));

        assertEq(lendingContract.liquidityContractAddress(), address(newLiquidityContract));
    }

    function testUpdateLiquidityContractAddress_works_after_transfer() public {
        NiftyApesLiquidity newLiquidityContract = new NiftyApesLiquidity();
        newLiquidityContract.initialize();

        vm.prank(EOA_2);
        vm.expectRevert("Ownable: caller is not the owner");
        lendingContract.updateLiquidityContractAddress(address(newLiquidityContract));
        vm.stopPrank();

        assertEq(lendingContract.liquidityContractAddress(), address(liquidityContract));

        vm.startPrank(EOA_1);
        lendingContract.transferOwnership(EOA_2);
        vm.stopPrank();

        vm.prank(EOA_2);
        lendingContract.updateLiquidityContractAddress(address(newLiquidityContract));
        vm.stopPrank();

        assertEq(lendingContract.liquidityContractAddress(), address(newLiquidityContract));
    }

    function testCannotUpdateLiquidityContractAddress_if_not_owner() public {
        NiftyApesLiquidity newLiquidityContract = new NiftyApesLiquidity();
        newLiquidityContract.initialize();

        vm.expectRevert("Ownable: caller is not the owner");
        lendingContract.updateLiquidityContractAddress(address(newLiquidityContract));

        assertEq(lendingContract.liquidityContractAddress(), address(liquidityContract));
    }

    function testCannotUpdateLiquidityContractAddress_if_not_owner_after_transfer() public {
        NiftyApesLiquidity newLiquidityContract = new NiftyApesLiquidity();
        newLiquidityContract.initialize();

        vm.startPrank(EOA_1);
        lendingContract.transferOwnership(EOA_2);
        vm.expectRevert("Ownable: caller is not the owner");
        lendingContract.updateLiquidityContractAddress(address(newLiquidityContract));
        vm.stopPrank();

        assertEq(lendingContract.liquidityContractAddress(), address(liquidityContract));
    }
}
