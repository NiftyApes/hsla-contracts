// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestLiquidityPauseSanctions is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function test_unit_pauseSanctions_works() public {
        vm.prank(owner);
        liquidity.pauseSanctions();

        vm.startPrank(usdcWhale);
        if (integration) {
            vm.expectRevert("Blacklistable: account is blacklisted");
        }
        usdcToken.transfer(SANCTIONED_ADDRESS, 1);
        vm.stopPrank();

        vm.startPrank(SANCTIONED_ADDRESS);
        if (integration) {
            vm.expectRevert("Blacklistable: account is blacklisted");
        }
        usdcToken.approve(address(liquidity), 1);

        if (integration) {
            vm.expectRevert("Blacklistable: account is blacklisted");
        }
        liquidity.supplyErc20(address(usdcToken), 1);
        vm.stopPrank();
    }

    function test_unit_cannot_pauseSanctions_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        liquidity.pauseSanctions();
    }

    function test_unit_unpauseSanctions_works() public {
        vm.prank(owner);
        liquidity.pauseSanctions();

        vm.startPrank(usdcWhale);
        if (integration) {
            vm.expectRevert("Blacklistable: account is blacklisted");
        }
        usdcToken.transfer(SANCTIONED_ADDRESS, 1);
        vm.stopPrank();

        vm.startPrank(SANCTIONED_ADDRESS);
        if (integration) {
            vm.expectRevert("Blacklistable: account is blacklisted");
        }
        usdcToken.approve(address(liquidity), 1);

        if (integration) {
            vm.expectRevert("Blacklistable: account is blacklisted");
        }
        liquidity.supplyErc20(address(usdcToken), 1);
        vm.stopPrank();

        vm.prank(owner);
        liquidity.unpauseSanctions();

        vm.startPrank(SANCTIONED_ADDRESS);
        vm.expectRevert("00017");
        liquidity.withdrawErc20(address(usdcToken), 1);
    }

    function test_unit_cannot_unpauseSanctions_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        liquidity.unpauseSanctions();
    }
}
