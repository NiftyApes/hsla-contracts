// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestCalculateProtocolInterestRatePerSecond is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function test_unit_test_1() public {
        uint256 interestRateBps = 10000;
        uint256 amount = 1_000_000_000_000 ether;
        uint256 duration = 30 * 52 weeks;
        uint256 maxBps = 10000;

        uint256 IRPS = ((amount * interestRateBps) / duration) / maxBps;

        console.log("(amount * interestRateBps)", (amount * interestRateBps));
        console.log(
            "((amount * interestRateBps) / duration)",
            ((amount * interestRateBps) / duration)
        );
        console.log(
            "((amount * interestRateBps) / duration) / maxBps",
            ((amount * interestRateBps) / duration) / maxBps
        );

        console.log("IRPS", IRPS);

        uint256 interestRateResult = ((IRPS * duration) * maxBps) / amount;

        console.log("(IRPS * duration)", (IRPS * duration));
        console.log("(IRPS * duration) * maxBps", (IRPS * duration) * maxBps);
        console.log("((IRPS * duration) * maxBps) / amount", ((IRPS * duration) * maxBps) / amount);

        console.log("interestRateResult", interestRateResult);
    }

    function test_unit_test_2() public {
        uint256 interestRateBps = 100;
        uint256 amount = 1 ether;
        uint256 duration = 86400;
        uint256 maxBps = 10000;

        uint256 IRPS = ((amount * interestRateBps) / duration) / maxBps;

        console.log("IRPS", IRPS);

        uint256 result = 115740740740;

        uint256 interestRateBps1 = 100;
        uint256 amount1 = 18446744073962011593;
        uint256 duration1 = 86400;
        uint256 maxBps1 = 10000;

        uint256 IRPS1 = ((amount1 * interestRateBps1) / duration1) / maxBps1;

        console.log("IRPS1", IRPS1);

        uint256 calcValue = (uint256(28) * amount1) / 250000000;

        console.log("(uint256(115740740740) * amount1)", (uint256(28) * amount1));
        console.log(
            "(uint256(115740740740) * amount1) / amount",
            (uint256(28) * amount1) / 250000000
        );
        console.log("calcValue", calcValue);
    }
}
