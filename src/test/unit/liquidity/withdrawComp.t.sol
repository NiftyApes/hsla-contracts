// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestWithdrawComp is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function test_unit_withdrawComp_works() public {
        if (integration) {
            vm.prank(compWhale);
            compToken.transfer(address(liquidity), 1 ether);
        } else {
            compToken.mint(address(liquidity), 1 ether);
        }

        vm.prank(owner);
        liquidity.withdrawComp();
    }

    function test_unit_cannot_withdrawComp_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        liquidity.withdrawComp();
    }
}
