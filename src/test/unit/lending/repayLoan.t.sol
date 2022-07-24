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

    function test_fuzz_repayLoan_simplest_case(
        FuzzedOfferFields memory fuzzedOffer,
        uint16 secondsBeforeRepayment
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        Offer memory offerToCreate = offerStructFromFields(fuzzedOffer, defaultFixedOfferFields);

        (Offer memory offer, ) = createOfferAndTryToExecuteLoanByBorrower(
            offerToCreate,
            "should work"
        );

        assertionsForExecutedLoan(offer);

        vm.warp(block.timestamp + secondsBeforeRepayment);

        uint256 interest = offer.interestRatePerSecond * secondsBeforeRepayment;

        if (offer.asset == address(daiToken)) {
            // Give borrower enough to pay interest
            mintUsdc(borrower1, interest);

            uint256 liquidityBalanceBeforeRepay = cDAIToken.balanceOf(address(liquidity));

            vm.startPrank(borrower1);
            daiToken.increaseAllowance(address(liquidity), ~uint256(0));
            lending.repayLoan(
                defaultFixedOfferFields.nftContractAddress,
                defaultFixedOfferFields.nftId
            );
            vm.stopPrank();

            // Liquidity contract cToken balance
            assertEq(
                cDAIToken.balanceOf(address(liquidity)),
                liquidityBalanceBeforeRepay +
                    liquidity.assetAmountToCAssetAmount(address(daiToken), offer.amount + interest)
            );

            // Borrower back to 0
            assertEq(daiToken.balanceOf(address(borrower1)), 0);

            // Lender back with interest
            assertCloseEnough(
                defaultUsdcLiquiditySupplied + interest,
                assetBalance(lender1, address(daiToken)),
                assetBalancePlusOneCToken(lender1, address(daiToken))
            );
        } else {
            uint256 liquidityBalanceBeforeRepay = cEtherToken.balanceOf(address(liquidity));

            vm.startPrank(borrower1);
            lending.repayLoan{ value: offer.amount + interest }(
                defaultFixedOfferFields.nftContractAddress,
                defaultFixedOfferFields.nftId
            );
            vm.stopPrank();

            // Liquidity contract cToken balance
            assertEq(
                cEtherToken.balanceOf(address(liquidity)),
                liquidityBalanceBeforeRepay +
                    liquidity.assetAmountToCAssetAmount(
                        address(ETH_ADDRESS),
                        offer.amount + interest
                    )
            );

            // Borrower back to initial minus interest
            assertEq(address(borrower1).balance, defaultInitialEthBalance - interest);

            // Lender back with interest
            assertCloseEnough(
                defaultEthLiquiditySupplied + interest,
                assetBalance(lender1, address(ETH_ADDRESS)),
                assetBalancePlusOneCToken(lender1, address(ETH_ADDRESS))
            );
        }
    }
}
