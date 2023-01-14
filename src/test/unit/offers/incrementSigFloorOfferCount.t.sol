// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersEvents.sol";

contract TestIncrementSigFloorOfferCount is Test, IOffersEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_IncrementSigFloorOfferCount_happyCase(Offer memory offer) public {
        bytes memory signature = signOffer(lender1_private_key, offer);

        approveLending(offer);
        vm.startPrank(borrower1);
        sigLending.executeLoanByBorrowerSignature(offer, signature, 1);
        vm.stopPrank();

        assertEq(offers.getSigFloorOfferCount(signature), 1);
    }

    function test_fuzz_IncrementSigFloorOfferCount_lender_721_happy_case(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        vm.assume(fuzzed.floorTerm == true);
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        _test_IncrementSigFloorOfferCount_happyCase(offer);
    }

    function test_fuzz_IncrementSigFloorOfferCount_lender_1155_happy_case(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        vm.assume(fuzzed.floorTerm == true);
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        offer.nftContractAddress = address(mockERC1155Token);
        offer.nftId = 1;
        _test_IncrementSigFloorOfferCount_happyCase(offer);
    }
}
