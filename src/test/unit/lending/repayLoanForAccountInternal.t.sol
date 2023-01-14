// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";

contract TestRepayLoanForAccountInternal is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function assertionsForExecutedLoan(Offer memory offer) private {
        // borrower has money
        if (offer.asset == address(daiToken)) {
            assertEq(daiToken.balanceOf(borrower1), offer.amount);
        } else {
            assertEq(borrower1.balance, defaultInitialEthBalance + offer.amount);
        }
        // lending contract has NFT
        assertEq(mockNft.ownerOf(1), address(lending));
        // loan auction exists
        assertEq(lending.getLoanAuction(address(mockNft), 1).lastUpdatedTimestamp, block.timestamp);
    }

    function test_fuzz_CANNOT_repayLoanForAccountInternal_NonInternalContract(
        FuzzedOfferFields memory fuzzedOffer
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        Offer memory offer = offerStructFromFields(fuzzedOffer, defaultFixedOfferFields);

        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");
        assertionsForExecutedLoan(offer);

        vm.startPrank(borrower1);
        daiToken.approve(address(liquidity), offer.amount);
        vm.expectRevert("00031");
        lending.repayLoanForAccountInternal(offer.nftContractAddress, offer.nftId, 1);
        vm.stopPrank();
    }

    function test_unit_CANNOT_repayLoanForAccountInternal_NonInternalContract() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );

        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");
        assertionsForExecutedLoan(offer);

        vm.startPrank(borrower1);
        daiToken.approve(address(liquidity), offer.amount);
        vm.expectRevert("00031");
        lending.repayLoanForAccountInternal(offer.nftContractAddress, offer.nftId, 1);
        vm.stopPrank();
    }
}
