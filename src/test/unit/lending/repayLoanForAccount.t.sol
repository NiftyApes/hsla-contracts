// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";

contract TestRepayLoanForAccount is Test, OffersLoansRefinancesFixtures {
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

    function test_fuzz_repayLoanForAccount_simplest_case(
        FuzzedOfferFields memory fuzzedOffer,
        uint16 secondsBeforeRepayment,
        address repayer
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        vm.assume(repayer != borrower1);

        Offer memory offerToCreate = offerStructFromFields(fuzzedOffer, defaultFixedOfferFields);

        (
            Offer memory offer,
            LoanAuction memory loanAuction
        ) = createOfferAndTryToExecuteLoanByBorrower(offerToCreate, "should work");

        assertionsForExecutedLoan(offer);

        vm.warp(block.timestamp + secondsBeforeRepayment);

        uint256 interest = offer.interestRatePerSecond * secondsBeforeRepayment;

        if (offer.asset == address(daiToken)) {
            mintDai(repayer, offer.amount + interest);

            uint256 liquidityBalanceBeforeRepay = cDAIToken.balanceOf(address(liquidity));
            uint256 borrowerBalanceBeforeRepay = daiToken.balanceOf(borrower1);
            uint256 repayerBalanceBeforeRepay = daiToken.balanceOf(repayer);

            vm.startPrank(repayer);
            daiToken.approve(address(liquidity), offer.amount + interest);
            lending.repayLoanForAccount(
                defaultFixedOfferFields.nftContractAddress,
                defaultFixedOfferFields.nftId,
                loanAuction.loanBeginTimestamp
            );
            vm.stopPrank();

            // Liquidity contract cToken balance
            assertEq(
                cDAIToken.balanceOf(address(liquidity)),
                liquidityBalanceBeforeRepay +
                    liquidity.assetAmountToCAssetAmount(address(daiToken), offer.amount + interest)
            );

            // repayer balance unchanged
            assertEq(
                daiToken.balanceOf(repayer),
                repayerBalanceBeforeRepay - (offer.amount + interest)
            );

            // borrower balance unchanged
            assertEq(borrowerBalanceBeforeRepay, daiToken.balanceOf(borrower1));

            // lender back with interest
            assertCloseEnough(
                defaultUsdcLiquiditySupplied + interest,
                assetBalance(lender1, address(daiToken)),
                assetBalancePlusOneCToken(lender1, address(daiToken))
            );
        } else {
            vm.deal(repayer, offer.amount + interest);

            uint256 liquidityBalanceBeforeRepay = cEtherToken.balanceOf(address(liquidity));
            uint256 borrowerBalanceBeforeRepay = borrower1.balance;
            uint256 repayerBalanceBeforeRepay = repayer.balance;

            vm.startPrank(repayer);
            lending.repayLoanForAccount{ value: offer.amount + interest }(
                defaultFixedOfferFields.nftContractAddress,
                defaultFixedOfferFields.nftId,
                loanAuction.loanBeginTimestamp
            );
            vm.stopPrank();

            // liquidity contract cToken balance
            assertEq(
                cEtherToken.balanceOf(address(liquidity)),
                liquidityBalanceBeforeRepay +
                    liquidity.assetAmountToCAssetAmount(
                        address(ETH_ADDRESS),
                        offer.amount + interest
                    )
            );

            // repayer balance unchanged
            assertEq(repayer.balance, repayerBalanceBeforeRepay - (offer.amount + interest));

            // borrower balance unchanged
            assertEq(borrowerBalanceBeforeRepay, borrower1.balance);

            // lender back with interest
            assertCloseEnough(
                defaultEthLiquiditySupplied + interest,
                assetBalance(lender1, address(ETH_ADDRESS)),
                assetBalancePlusOneCToken(lender1, address(ETH_ADDRESS))
            );
        }
    }
}
