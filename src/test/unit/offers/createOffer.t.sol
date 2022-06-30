// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersEvents.sol";

contract TestCreateOffer is Test, IOffersEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function test_unit_cannot_createOffer_if_offer_expired(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        offer.expiration = uint32(block.timestamp - 1);

        vm.expectRevert("00010");
        vm.startPrank(lender1);
        offers.createOffer(offer);
    }

    function test_unit_cannot_createOffer_if_offer_duration_less_than_24_hours(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        offer.duration = 1 days - 1 seconds;

        vm.expectRevert("00011");
        vm.startPrank(lender1);
        offers.createOffer(offer);
    }
}
