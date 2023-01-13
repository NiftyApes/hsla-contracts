// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/cryptography/draft-EIP712Upgradeable.sol";
import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersEvents.sol";

contract TestGetOfferHash is Test, IOffersEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function test_unit_getOfferHash() public {
        Offer memory offer = Offer({
            creator: lender1,
            nftContractAddress: address(0xB4FFCD625FefD541b77925c7A37A55f488bC69d9),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(0x18669eb6c7dFc21dCdb787fEb4B3F1eBb3172400),
            amount: 6,
            duration: 1 days,
            expiration: uint32(1657217355),
            floorTermLimit: 1
        });

        bytes32 functionOfferHash = offers.getOfferHash(offer);

        bytes32 expectedFunctionHash = 0xb6c5e5d04568260fce01c735477a05f4022cee5cd48059092bdc22cfee3139db;

        assertEq(functionOfferHash, expectedFunctionHash);
    }
}
