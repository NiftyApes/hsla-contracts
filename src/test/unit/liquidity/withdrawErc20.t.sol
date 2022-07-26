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
}
