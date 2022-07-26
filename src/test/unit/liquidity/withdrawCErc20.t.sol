// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestWithdrawCErc20 is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_withdrawCErc20_works(uint128 amount) private {
        if (integration) {
            vm.startPrank(daiWhale);
            daiToken.transfer(borrower1, daiToken.balanceOf(daiWhale));
            vm.stopPrank();
        } else {
            daiToken.mint(borrower1, 3672711471 ether);
        }

        vm.startPrank(borrower1);

        daiToken.approve(address(cDAIToken), daiToken.balanceOf(borrower1));

        cDAIToken.mint(daiToken.balanceOf(borrower1));
        uint256 cTokenBalanceAfter = cDAIToken.balanceOf(borrower1);

        console.log("cTokenBalanceAfter", cTokenBalanceAfter);

        // avoid `redeemTokens zero` error by providing at least 1 cDAI
        vm.assume(amount >= 100000000);
        vm.assume(amount < cDAIToken.balanceOf(borrower1));

        console.log("amount", amount);

        uint256 balanceBefore = liquidity.getCAssetBalance(borrower1, address(cDAIToken));
        console.log("balanceBefore", balanceBefore);

        assertEq(balanceBefore, 0);

        cDAIToken.approve(address(liquidity), amount);
        uint256 cTokensTransferred = liquidity.supplyCErc20(address(cDAIToken), amount);

        uint256 balanceAfterSupply = liquidity.getCAssetBalance(borrower1, address(cDAIToken));
        console.log("balanceAfterSupply", balanceAfterSupply);
        console.log("cTokensTransferred", cTokensTransferred);

        assertEq(balanceAfterSupply, cTokensTransferred);

        uint256 cTokensWithdrawn = liquidity.withdrawCErc20(address(cDAIToken), amount);
        uint256 balanceAfterWithdraw = liquidity.getCAssetBalance(borrower1, address(cDAIToken));
        console.log("cTokensWithdrawn", cTokensWithdrawn);
        console.log("balanceAfterWithdraw", balanceAfterWithdraw);

        assertEq(cTokensWithdrawn, balanceAfterSupply);
        assertEq(balanceAfterWithdraw, 0);

        vm.stopPrank();
    }

    function test_fuzz_withdrawCErc20_works(uint128 amount) public {
        _test_withdrawCErc20_works(amount);
    }

    function test_unit_withdrawCErc20_works() public {
        uint128 amount = 100000000;

        _test_withdrawCErc20_works(amount);
    }
}
