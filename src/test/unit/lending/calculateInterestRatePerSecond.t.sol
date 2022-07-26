// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestCalculateInterestRatePerSecond is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function test_unit_calculateInterestRatePerSecond_math() public {
        uint256 interestBps = 10000;
        uint256 amount = 1 ether;
        uint256 duration = 30 * 52 weeks;
        uint256 maxBps = 10000;

        uint256 IRPS = ((amount * interestBps) / duration) / maxBps;

        assertEq(1059896893, IRPS);
    }

    function test_unit_calculateInterestBps_math() public {
        uint256 interestRatePerSecond = 1;
        uint256 amount = 864000000;
        uint256 duration = 1 days;
        uint256 maxBps = 10000;

        console.log("(interestRatePerSecond * duration)", (interestRatePerSecond * duration));
        console.log(
            "((interestRatePerSecond * duration) * maxBps)",
            ((interestRatePerSecond * duration) * maxBps)
        );
        console.log(
            "((interestRatePerSecond * duration) * maxBps) / amount + 1",
            ((interestRatePerSecond * duration) * maxBps) / amount + 1
        );

        uint256 interestRateResult = (((interestRatePerSecond * duration) * maxBps) / amount + 1);

        console.log("interestRateResult", interestRateResult);

        assertEq(1, interestRateResult);
    }

    function test_fuzz_calculateInterestRatePerSecond_math(
        uint256 interestBps,
        uint256 amount,
        uint256 duration
    ) public {
        uint256 maxBps = 10000;

        vm.assume(interestBps > 0);
        vm.assume(interestBps <= 1000000);
        vm.assume(amount > 0);
        vm.assume(amount <= defaultEthLiquiditySupplied);
        vm.assume(duration >= 1 days);
        vm.assume(duration <= ~uint32(0));

        console.log("(amount * interestBps)", (amount * interestBps));
        console.log("(amount * interestBps) / duration", (amount * interestBps) / maxBps);

        console.log(
            "((amount * interestBps) / maxBps) / duration",
            ((amount * interestBps) / maxBps) / duration
        );

        uint256 IRPS = ((amount * interestBps) / maxBps) / duration;

        if (IRPS == 0 && interestBps != 0) {
            IRPS = 1;
        }

        console.log("IRPS", IRPS);

        uint96 calcResult = lending.calculateInterestPerSecond(amount, interestBps, duration);

        assertEq(calcResult, IRPS);
    }
}
