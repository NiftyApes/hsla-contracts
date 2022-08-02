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

        (, uint256 accruedProtocolInterest) = lending.calculateInterestAccrued(
            defaultFixedOfferFields.nftContractAddress,
            defaultFixedOfferFields.nftId
        );

        uint256 protocolInterest = loanAuction.accumulatedPaidProtocolInterest +
            loanAuction.unpaidProtocolInterest +
            accruedProtocolInterest;

        uint256 interest = (offer.interestRatePerSecond * secondsBeforeRepayment) +
            protocolInterest;

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
            console.log("here");
            // Liquidity contract cToken balance
            assertEq(
                cDAIToken.balanceOf(address(liquidity)),
                liquidityBalanceBeforeRepay +
                    liquidity.assetAmountToCAssetAmount(address(daiToken), offer.amount + interest)
            );
            console.log("here 1");

            // repayer balance unchanged
            assertEq(
                daiToken.balanceOf(repayer),
                repayerBalanceBeforeRepay - (offer.amount + interest)
            );
            console.log("here 2");

            // borrower balance unchanged
            assertEq(borrowerBalanceBeforeRepay, daiToken.balanceOf(borrower1));
            console.log("here 3");

            // lender back with interest
            assertCloseEnough(
                defaultDaiLiquiditySupplied + interest,
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
            console.log("here 4");

            // liquidity contract cToken balance
            assertEq(
                cEtherToken.balanceOf(address(liquidity)),
                liquidityBalanceBeforeRepay +
                    liquidity.assetAmountToCAssetAmount(
                        address(ETH_ADDRESS),
                        offer.amount + interest
                    )
            );
            console.log("here 5");

            // repayer balance unchanged
            assertEq(repayer.balance, repayerBalanceBeforeRepay - (offer.amount + interest));
            console.log("here 6");

            // borrower balance unchanged
            assertEq(borrowerBalanceBeforeRepay, borrower1.balance);
            console.log("here 7");

            // lender back with interest
            assertCloseEnough(
                defaultEthLiquiditySupplied + interest,
                assetBalance(lender1, address(ETH_ADDRESS)),
                assetBalancePlusOneCToken(lender1, address(ETH_ADDRESS))
            );
        }
    }
}
