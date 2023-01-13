// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersEvents.sol";

contract TestCreateOffer is Test, IOffersEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_createOffer_happyCase(Offer memory offer) public {
        vm.startPrank(offer.creator);
        offers.createOffer(offer);
        vm.stopPrank();
        bytes32 offerHash = offers.getOfferHash(offer);
        Offer memory offerOnChain = offers.getOffer(offerHash);
        assertEq(offer.creator, offerOnChain.creator);
        assertEq(offer.duration, offerOnChain.duration);
        assertEq(offer.expiration, offerOnChain.expiration);
        assertEq(offer.fixedTerms, offerOnChain.fixedTerms);
        assertEq(offer.floorTerm, offerOnChain.floorTerm);
        assertEq(offer.lenderOffer, offerOnChain.lenderOffer);
        assertEq(offer.nftContractAddress, offerOnChain.nftContractAddress);
        assertEq(offer.asset, offerOnChain.asset);
        assertEq(offer.amount, offerOnChain.amount);
        assertEq(offer.interestRatePerSecond, offerOnChain.interestRatePerSecond);
        assertEq(offer.floorTermLimit, offerOnChain.floorTermLimit);
    }

    function test_fuzz_createOffer_lender_721_happy_case(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        _test_createOffer_happyCase(offer);
    }

    function test_fuzz_createOffer_lender_1155_happy_case(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        offer.nftContractAddress = address(mockERC1155Token);
        offer.nftId = 1;
        _test_createOffer_happyCase(offer);
    }

    function test_fuzz_createOffer_borrower_721_happy_case(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        vm.assume(fuzzed.floorTerm == false);
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedBorrowerOfferFields);
        _test_createOffer_happyCase(offer);
    }

    function test_fuzz_createOffer_borrower_1155_happy_case(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        vm.assume(fuzzed.floorTerm == false);
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedBorrowerOfferFields);
        offer.nftContractAddress = address(mockERC1155Token);
        offer.nftId = 1;
        _test_createOffer_happyCase(offer);
    }

    function test_fuzz_cannot_createOffer_if_offer_expired(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        offer.expiration = uint32(block.timestamp - 1);

        vm.expectRevert("00010");
        vm.startPrank(lender1);
        offers.createOffer(offer);
    }

    function test_fuzz_cannot_createOffer_if_offer_duration_less_than_24_hours(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        offer.duration = 1 days - 1 seconds;

        vm.expectRevert("00011");
        vm.startPrank(lender1);
        offers.createOffer(offer);
    }

    function test_fuzz_cannot_createOffer_not_NFT_owner(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedBorrowerOfferFields);

        offer.nftId = 2;

        vm.expectRevert("00021");
        vm.startPrank(borrower1);
        offers.createOffer(offer);
    }

    function test_fuzz_cannot_createOffer_no_floor_terms_for_borrower_offer(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedBorrowerOfferFields);

        offer.floorTerm = true;

        vm.expectRevert("00014");
        vm.startPrank(borrower1);
        offers.createOffer(offer);
    }

    function test_fuzz_cannot_createOffer_offerHash_already_exists(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedBorrowerOfferFields);

        offer.floorTerm = false;

        vm.startPrank(borrower1);
        offers.createOffer(offer);

        vm.expectRevert("00046");
        offers.createOffer(offer);
    }

    function test_fuzz_cannot_createOffer_msgSenderDoesnNotEqualOfferCreator(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedBorrowerOfferFields);

        offer.floorTerm = false;

        vm.startPrank(lender1);
        vm.expectRevert("00024");
        offers.createOffer(offer);
    }

    function test_fuzz_cannot_createOffer_erc1155_if_tokenId_fungible(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        offer.nftContractAddress = address(mockERC1155Token);
        offer.nftId = 2;

        vm.expectRevert("00070");
        vm.startPrank(lender1);
        offers.createOffer(offer);
    }

    function test_fuzz_cannot_createOffer_erc1155_not_NFT_owner(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        vm.assume(fuzzed.floorTerm == false);
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedBorrowerOfferFields);
        offer.nftContractAddress = address(mockERC1155Token);
        offer.nftId = 3;

        vm.expectRevert("00021");
        vm.startPrank(borrower1);
        offers.createOffer(offer);
    }
}
