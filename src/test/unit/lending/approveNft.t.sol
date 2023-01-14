// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestApproveNft is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function test_cannot_unit_approveNft_notSellOnSeaport() public {
        Offer memory offer = offerStructFromFields(defaultFixedFuzzedFieldsForFastUnitTesting, defaultFixedOfferFields);
        
        vm.startPrank(borrower1);
        vm.expectRevert("00031");
        lending.approveNft(offer.nftContractAddress, offer.nftId, borrower1);
        vm.stopPrank();
    }
}
