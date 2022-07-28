// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestWithdrawErc20 is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_withdrawErc20_works(uint128 amount) private {
        if (integration) {
            vm.startPrank(daiWhale);
            daiToken.transfer(borrower1, daiToken.balanceOf(daiWhale));
            vm.stopPrank();
        } else {
            daiToken.mint(borrower1, 3672711471 ether);
        }
        // avoid `redeemTokens zero` error by providing at least 1 DAI
        vm.assume(amount >= 1 ether);
        vm.assume(amount <= daiToken.balanceOf(borrower1));

        console.log("amount", amount);

        uint256 balanceBefore = liquidity.getCAssetBalance(borrower1, address(cDAIToken));
        console.log("balanceBefore", balanceBefore);

        assertEq(balanceBefore, 0);

        vm.startPrank(borrower1);
        daiToken.approve(address(liquidity), amount);
        uint256 cTokensMinted = liquidity.supplyErc20(address(daiToken), amount);

        uint256 balanceAfterSupply = liquidity.getCAssetBalance(borrower1, address(cDAIToken));
        console.log("balanceAfterSupply", balanceAfterSupply);
        console.log("cTokensMinted", cTokensMinted);

        assertEq(balanceAfterSupply, cTokensMinted);

        uint256 cTokensWithdrawn = liquidity.withdrawErc20(address(daiToken), amount);
        uint256 balanceAfterWithdraw = liquidity.getCAssetBalance(borrower1, address(cDAIToken));
        console.log("cTokensWithdrawn", cTokensWithdrawn);
        console.log("balanceAfterWithdraw", balanceAfterWithdraw);

        uint256 underlyingWithdrawn = liquidity.cAssetAmountToAssetAmount(
            address(cDAIToken),
            cTokensWithdrawn
        );
        console.log("amount", amount);
        console.log("underlyingWithdrawn", underlyingWithdrawn);

        assertEq(cTokensWithdrawn, balanceAfterSupply);
        assertEq(balanceAfterWithdraw, 0);
        isApproxEqual(amount, underlyingWithdrawn, 1);

        vm.stopPrank();
    }

    function test_fuzz_withdrawErc20_works(uint128 amount) public {
        _test_withdrawErc20_works(amount);
    }

    function test_unit_withdrawErc20_works() public {
        uint128 amount = 1 ether;

        _test_withdrawErc20_works(amount);
    }

    function _test_withdrawErc20_owner_works(uint128 amount) private {
        if (integration) {
            vm.startPrank(daiWhale);
            daiToken.transfer(owner, daiToken.balanceOf(daiWhale));
            vm.stopPrank();
        } else {
            daiToken.mint(owner, 3672711471 ether);
        }
        // avoid `redeemTokens zero` error by providing at least 1 DAI
        vm.assume(amount >= 1 ether);
        vm.assume(amount <= daiToken.balanceOf(owner));

        console.log("amount", amount);
        uint256 daiBalanceBefore = daiToken.balanceOf(owner);
        uint256 regenBalanceBefore = daiToken.balanceOf(liquidity.regenCollectiveAddress());

        console.log("daiBalanceBefore", daiBalanceBefore);
        console.log("regenBalanceBefore", regenBalanceBefore);

        uint256 balanceBefore = liquidity.getCAssetBalance(owner, address(cDAIToken));
        console.log("balanceBefore", balanceBefore);

        assertEq(balanceBefore, 0);
        assertEq(regenBalanceBefore, 0);

        vm.startPrank(owner);
        daiToken.approve(address(liquidity), amount);
        uint256 cTokensMinted = liquidity.supplyErc20(address(daiToken), amount);

        uint256 balanceAfterSupply = liquidity.getCAssetBalance(owner, address(cDAIToken));
        console.log("balanceAfterSupply", balanceAfterSupply);
        console.log("cTokensMinted", cTokensMinted);

        assertEq(balanceAfterSupply, cTokensMinted);

        uint256 cTokensWithdrawn = liquidity.withdrawErc20(address(daiToken), amount);
        uint256 balanceAfterWithdraw = liquidity.getCAssetBalance(owner, address(cDAIToken));
        console.log("cTokensWithdrawn", cTokensWithdrawn);
        console.log("balanceAfterWithdraw", balanceAfterWithdraw);

        uint256 underlyingWithdrawn = liquidity.cAssetAmountToAssetAmount(
            address(cDAIToken),
            cTokensWithdrawn
        );

        console.log("amount", amount);
        console.log("underlyingWithdrawn", underlyingWithdrawn);

        uint256 daiBalanceAfter = daiToken.balanceOf(owner);
        uint256 regenBalanceAfter = daiToken.balanceOf(liquidity.regenCollectiveAddress());

        console.log("daiBalanceAfter", daiBalanceAfter);
        console.log("regenBalanceAfter", regenBalanceAfter);

        uint256 expectedRegenAmount = (amount * liquidity.regenCollectiveBpsOfRevenue()) / 10_000;

        console.log("expectedRegenAmount", expectedRegenAmount);

        isApproxEqual(cTokensWithdrawn, balanceAfterSupply, 1);
        isApproxEqual(balanceAfterWithdraw, 0, 1);
        isApproxEqual(amount, underlyingWithdrawn, 1);
        isApproxEqual((expectedRegenAmount), (daiBalanceBefore - daiBalanceAfter), 1);
        isApproxEqual(expectedRegenAmount, regenBalanceAfter, 1);

        vm.stopPrank();
    }

    function test_fuzz_withdrawErc20_owner_works(uint128 amount) public {
        _test_withdrawErc20_owner_works(amount);
    }

    function test_unit_withdrawErc20_owner_works() public {
        uint128 amount = 1 ether;

        _test_withdrawErc20_owner_works(amount);
    }
}
