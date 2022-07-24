// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";

contract TestPartialRepayLoan is Test, OffersLoansRefinancesFixtures {
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

    function test_unit_partialRepayLoan_does_not_reset_gas_griefing() public {
        uint16 secondsBeforeRepayment = 12 hours;

        Offer memory offerToCreate = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );

        (Offer memory offer, ) = createOfferAndTryToExecuteLoanByBorrower(
            offerToCreate,
            "should work"
        );

        assertionsForExecutedLoan(offer);

        vm.warp(block.timestamp + secondsBeforeRepayment);

        uint256 interest = offer.interestRatePerSecond * secondsBeforeRepayment;

        uint256 interestShortfallBeforePartialPayment = lending.checkSufficientInterestAccumulated(
            offer.nftContractAddress,
            offer.nftId
        );

        if (offer.asset == address(daiToken)) {
            mintUsdc(borrower1, 1);

            vm.startPrank(borrower1);
            daiToken.increaseAllowance(address(liquidity), ~uint256(0));
            lending.partialRepayLoan(
                defaultFixedOfferFields.nftContractAddress,
                defaultFixedOfferFields.nftId,
                1
            );
            vm.stopPrank();
        } else {
            vm.startPrank(borrower1);
            lending.partialRepayLoan{ value: offer.amount + interest }(
                defaultFixedOfferFields.nftContractAddress,
                defaultFixedOfferFields.nftId,
                1
            );
            vm.stopPrank();
        }

        uint256 interestShortfallAfter = lending.checkSufficientInterestAccumulated(
            offer.nftContractAddress,
            offer.nftId
        );

        assertEq(interestShortfallBeforePartialPayment, 0);
        assertEq(interestShortfallAfter, 24999);
    }
}
