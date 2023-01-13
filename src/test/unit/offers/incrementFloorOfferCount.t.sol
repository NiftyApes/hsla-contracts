// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersEvents.sol";

contract TestIncrementFloorOfferCount is Test, IOffersEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_incrementFloorOfferCount_happyCase(Offer memory offer) public {
        vm.startPrank(offer.creator);
        offers.createOffer(offer);
        vm.stopPrank();
        bytes32 offerHash = offers.getOfferHash(offer);
        assertEq(offers.getFloorOfferCount(offerHash), 0);

        approveLending(offer);
        tryToExecuteLoanByBorrower(offer, "should work");
        assertEq(offers.getFloorOfferCount(offerHash), 1);
    }

    function test_fuzz_incrementFloorOfferCount_lender_721_happy_case(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        vm.assume(fuzzed.floorTerm == true);
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        _test_incrementFloorOfferCount_happyCase(offer);
    }

    function test_fuzz_incrementFloorOfferCount_lender_1155_happy_case(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        vm.assume(fuzzed.floorTerm == true);
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        offer.nftContractAddress = address(mockERC1155Token);
        offer.nftId = 1;
        _test_incrementFloorOfferCount_happyCase(offer);
    }
}
