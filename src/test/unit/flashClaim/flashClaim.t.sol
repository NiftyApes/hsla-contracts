// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestFlashClaim is Test, ILendingEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_unit_flashClaim_simplest_case(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        vm.startPrank(borrower1);
        flashClaim.flashClaim(
            address(flashClaimReceiverHappy),
            offer.nftContractAddress,
            offer.nftId,
            bytes("")
        );
        vm.stopPrank();

        address nftOwner = IERC721Upgradeable(offer.nftContractAddress).ownerOf(offer.nftId);

        assertEq(address(lending), nftOwner);
    }

    function test_unit_flashClaim_simplest_case() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_flashClaim_simplest_case(fixedForSpeed);
    }

    function _test_unit_cannot_flashClaim_notNftOwner(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        vm.startPrank(borrower2);
        vm.expectRevert("00021");

        flashClaim.flashClaim(
            address(flashClaimReceiverNoReturn),
            offer.nftContractAddress,
            offer.nftId,
            bytes("")
        );
        vm.stopPrank();
    }

    function test_unit_cannot_flashClaim_notNftOwner() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cannot_flashClaim_notNftOwner(fixedForSpeed);
    }

    function _test_unit_cannot_flashClaim_noReturn(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        vm.startPrank(borrower1);
        vm.expectRevert("ERC721: caller is not token owner or approved");
        flashClaim.flashClaim(
            address(flashClaimReceiverNoReturn),
            offer.nftContractAddress,
            offer.nftId,
            bytes("")
        );
        vm.stopPrank();
    }

    function test_unit_cannot_flashClaim_noReturn() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cannot_flashClaim_noReturn(fixedForSpeed);
    }

    function test_unit_cannot_flashClaim_ReturnsFalse() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        Offer memory offer = offerStructFromFields(fixedForSpeed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        vm.startPrank(borrower1);
        vm.expectRevert("00058");
        flashClaim.flashClaim(
            address(flashClaimReceiverReturnsFalse),
            offer.nftContractAddress,
            offer.nftId,
            bytes("")
        );
        vm.stopPrank();
    }
}
