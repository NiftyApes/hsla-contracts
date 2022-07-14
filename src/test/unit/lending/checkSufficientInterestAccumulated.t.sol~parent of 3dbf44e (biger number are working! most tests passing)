// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestCheckSufficientInterestAccumulated is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_checkSufficientInterestAccumulated_works(
        uint128 amount,
        uint32 duration,
        uint16 protocolInterestBps
    ) private {
        vm.startPrank(owner);
        lending.updateProtocolInterestBps(protocolInterestBps);
        vm.stopPrank();

        uint96 protocolInterestPerSecond = lending.checkSufficientInterestAccumulated(
            amount,
            duration
        );

        uint96 expectedProtocolInterestPerSecond = uint96(
            (amount * protocolInterestBps) / MAX_BPS / duration
        );

        assertEq(protocolInterestPerSecond, expectedProtocolInterestPerSecond);
    }

    function test_fuzz_checkSufficientInterestAccumulated_works(
        uint128 amount,
        uint32 duration,
        uint16 protocolInterestBps
    ) public {
        vm.assume(amount > 0);
        // current total supply of ether
        vm.assume(amount < 121520307 ether);
        vm.assume(duration > 0);
        vm.assume(duration < ~uint32(0) - block.timestamp);
        vm.assume(protocolInterestBps <= MAX_FEE);
        _test_checkSufficientInterestAccumulated_works(amount, duration, protocolInterestBps);
    }

    function test_unit_checkSufficientInterestAccumulated_works() public {
        uint128 amount = 1 ether;
        uint32 duration = 1 days;
        uint16 protocolInterestBps = 100;

        _test_checkSufficientInterestAccumulated_works(amount, duration, protocolInterestBps);
    }
}
