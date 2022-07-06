// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";

contract TestRepayLoan is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function assertionsForExecutedLoan(Offer memory offer) private {
        // borrower has money
        if (offer.asset == address(usdcToken)) {
            assertEq(usdcToken.balanceOf(borrower1), offer.amount);
        } else {
            assertEq(borrower1.balance, defaultInitialEthBalance + offer.amount);
        }
        // lending contract has NFT
        assertEq(mockNft.ownerOf(1), address(lending));
        // loan auction exists
        assertEq(lending.getLoanAuction(address(mockNft), 1).lastUpdatedTimestamp, block.timestamp);
    }

    function test_fuzz_repayLoan_simplest_case(FuzzedOfferFields memory fuzzedOffer)
        public
        validateFuzzedOfferFields(fuzzedOffer)
    {
        Offer memory offerToCreate = offerStructFromFields(fuzzedOffer, defaultFixedOfferFields);

        (Offer memory offer, ) = createOfferAndTryToExecuteLoanByBorrower(
            offerToCreate,
            "should work"
        );

        assertionsForExecutedLoan(offer);

        vm.startPrank(borrower1);
        if (offer.asset == address(usdcToken)) {
            usdcToken.increaseAllowance(address(liquidity), ~uint256(0));
            lending.repayLoan(
                defaultFixedOfferFields.nftContractAddress,
                defaultFixedOfferFields.nftId
            );
        } else {
            lending.repayLoan{ value: offer.amount }(
                defaultFixedOfferFields.nftContractAddress,
                defaultFixedOfferFields.nftId
            );
        }

        vm.stopPrank();
    }
}
