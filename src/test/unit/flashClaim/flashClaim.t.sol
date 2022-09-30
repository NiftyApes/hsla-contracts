// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestLendingRenounceOwnership is Test, ILendingEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_unit_flashClaim_simplest_case(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        vm.startPrank(borrower1);
        flashClaim.flashClaim(offer.nftContractAddress, offer.nftId, address(flashClaimReceiver));
        vm.stopPrank();
    }

    function test_unit_flashClaim_simplest_case() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_flashClaim_simplest_case(fixedForSpeed);
    }
}
