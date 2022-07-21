// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";

contract TestDrawLoanAmount is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    // this is set up to have the borrower refinance
    // there's no reason to prefer borrower to lender here
    // or vice versa
    function refinanceSetup(
        FuzzedOfferFields memory fuzzed,
        uint16 secondsBeforeRefinance,
        uint256 amountExtraOnRefinance
    ) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        assertionsForExecutedLoan(offer);

        LoanAuction memory loanAuction = lending.getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );

        vm.warp(block.timestamp + secondsBeforeRefinance);

        uint256 interestShortfall = lending.checkSufficientInterestAccumulated(
            offer.nftContractAddress,
            offer.nftId
        );

        (, uint256 protocolInterest) = lending.calculateInterestAccrued(
            offer.nftContractAddress,
            offer.nftId
        );

        // will trigger gas griefing (but not term griefing with borrower refinance)
        defaultFixedOfferFields.creator = lender2;
        fuzzed.floorTerm = false; // refinance can't be floor term
        fuzzed.expiration = uint32(block.timestamp) + secondsBeforeRefinance + 1;
        fuzzed.amount = uint128(
            offer.amount +
                (offer.interestRatePerSecond * secondsBeforeRefinance) +
                interestShortfall +
                protocolInterest +
                amountExtraOnRefinance
        );
        console.log("offer.amount", offer.amount);

        console.log(
            "(offer.interestRatePerSecond * secondsBeforeRefinance)",
            (offer.interestRatePerSecond * secondsBeforeRefinance)
        );
        console.log("interestShortfall", interestShortfall);
        console.log("protocolInterest", protocolInterest);

        console.log("amountExtraOnRefinance", amountExtraOnRefinance);

        console.log("fuzzed.amount", fuzzed.amount);

        console.log("loanAuction.amount", loanAuction.amount);

        Offer memory newOffer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        uint256 beforeRefinanceLenderBalance = assetBalance(lender1, address(usdcToken));

        if (offer.asset == address(usdcToken)) {
            beforeRefinanceLenderBalance = assetBalance(lender1, address(usdcToken));
        } else {
            beforeRefinanceLenderBalance = assetBalance(lender1, ETH_ADDRESS);
        }

        tryToRefinanceLoanByBorrower(newOffer, "should work");

        LoanAuction memory loanAuction2 = lending.getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );

        console.log("loanAuction.amount 2", loanAuction2.amount);

        assertionsForExecutedRefinance(
            offer,
            loanAuction.amountDrawn,
            secondsBeforeRefinance,
            interestShortfall,
            beforeRefinanceLenderBalance
        );
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

    function assertionsForExecutedRefinance(
        Offer memory offer,
        uint256 amountDrawn,
        uint16 secondsBeforeRefinance,
        uint256 interestShortfall,
        uint256 beforeRefinanceLenderBalance
    ) private {
        // lender1 has money
        if (offer.asset == address(usdcToken)) {
            assertBetween(
                beforeRefinanceLenderBalance +
                    amountDrawn +
                    (offer.interestRatePerSecond * secondsBeforeRefinance) +
                    interestShortfall,
                assetBalance(lender1, address(usdcToken)),
                assetBalancePlusOneCToken(lender1, address(usdcToken))
            );
        } else {
            assertBetween(
                beforeRefinanceLenderBalance +
                    amountDrawn +
                    (offer.interestRatePerSecond * secondsBeforeRefinance) +
                    interestShortfall,
                assetBalance(lender1, ETH_ADDRESS),
                assetBalancePlusOneCToken(lender1, ETH_ADDRESS)
            );
        }
    }

    function test_fuzz_drawLoanAmount_simplest_case(
        FuzzedOfferFields memory fuzzedOffer,
        uint16 secondsBeforeRefinance,
        uint64 amountExtraOnRefinance,
        bool excessDraw
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        vm.assume(amountExtraOnRefinance > 0);
        // since we add 1 to amountExtraOnRefinance sometimes below
        // we want to make sure adding 1 doesn't overflow
        vm.assume(amountExtraOnRefinance < ~uint64(0));
        if (fuzzedOffer.randomAsset % 2 == 0) {
            vm.assume(amountExtraOnRefinance < (defaultUsdcLiquiditySupplied * 2) / 100);
        } else {
            vm.assume(amountExtraOnRefinance < (defaultEthLiquiditySupplied * 2) / 100);
        }

        bool isRefinanceExtraEnough; // to avoid "redeemTokens zero" when borrower draws more
        if (fuzzedOffer.randomAsset % 2 == 0) {
            isRefinanceExtraEnough =
                amountExtraOnRefinance >= 10 * uint128(10**usdcToken.decimals());
        } else {
            isRefinanceExtraEnough = amountExtraOnRefinance >= 250000000;
        }

        amountExtraOnRefinance = isRefinanceExtraEnough
            ? amountExtraOnRefinance
            : uint64(
                fuzzedOffer.randomAsset % 2 == 0
                    ? 10 * uint128(10**usdcToken.decimals())
                    : 250000000
            );

        refinanceSetup(fuzzedOffer, secondsBeforeRefinance, amountExtraOnRefinance);

        vm.startPrank(borrower1);
        if (excessDraw) {
            vm.expectRevert("00020");
        }

        lending.drawLoanAmount(
            defaultFixedOfferFields.nftContractAddress,
            defaultFixedOfferFields.nftId,
            excessDraw ? amountExtraOnRefinance + 1 : amountExtraOnRefinance
        );
        vm.stopPrank();
    }

    function test_fuzz_drawLoanAmount_math_works(
        FuzzedOfferFields memory fuzzedOffer,
        uint16 secondsBeforeRefinance,
        uint64 amountExtraOnRefinance
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        vm.startPrank(owner);
        lending.updateProtocolInterestBps(100);
        vm.stopPrank();

        vm.assume(amountExtraOnRefinance > 0);
        // since we add 1 to amountExtraOnRefinance sometimes below
        // we want to make sure adding 1 doesn't overflow
        vm.assume(amountExtraOnRefinance < ~uint64(0));
        if (fuzzedOffer.randomAsset % 2 == 0) {
            vm.assume(amountExtraOnRefinance < (defaultUsdcLiquiditySupplied * 2) / 100);
        } else {
            vm.assume(amountExtraOnRefinance < (defaultEthLiquiditySupplied * 2) / 100);
        }

        bool isRefinanceExtraEnough; // to avoid "redeemTokens zero" when borrower draws more
        if (fuzzedOffer.randomAsset % 2 == 0) {
            isRefinanceExtraEnough =
                amountExtraOnRefinance >= 10 * uint128(10**usdcToken.decimals());
        } else {
            isRefinanceExtraEnough = amountExtraOnRefinance >= 250000000;
        }

        amountExtraOnRefinance = isRefinanceExtraEnough
            ? amountExtraOnRefinance
            : uint64(
                fuzzedOffer.randomAsset % 2 == 0
                    ? 10 * uint128(10**usdcToken.decimals())
                    : 250000000
            );

        refinanceSetup(fuzzedOffer, secondsBeforeRefinance, amountExtraOnRefinance);

        LoanAuction memory loanAuctionBefore = lending.getLoanAuction(
            defaultFixedOfferFields.nftContractAddress,
            defaultFixedOfferFields.nftId
        );

        console.log("loanAuctionBefore.amount", loanAuctionBefore.amount);
        console.log("loanAuctionBefore.amountDrawn", loanAuctionBefore.amountDrawn);
        console.log("loanAuctionBefore.loanEndTimestamp", loanAuctionBefore.loanEndTimestamp);
        console.log("loanAuctionBefore.loanBeginTimestamp", loanAuctionBefore.loanBeginTimestamp);

        uint256 amountDrawnBefore = loanAuctionBefore.amountDrawn;

        uint256 interestRatePerSecondBefore = loanAuctionBefore.interestRatePerSecond;
        uint256 protocolInterestRatePerSecondBefore = loanAuctionBefore
            .protocolInterestRatePerSecond;

        console.log("interestRatePerSecondBefore", interestRatePerSecondBefore);
        console.log("protocolInterestRatePerSecondBefore", protocolInterestRatePerSecondBefore);

        vm.startPrank(borrower1);
        lending.drawLoanAmount(
            defaultFixedOfferFields.nftContractAddress,
            defaultFixedOfferFields.nftId,
            amountExtraOnRefinance
        );
        vm.stopPrank();

        LoanAuction memory loanAuctionAfter = lending.getLoanAuction(
            defaultFixedOfferFields.nftContractAddress,
            defaultFixedOfferFields.nftId
        );

        uint256 interestRatePerSecondAfter = loanAuctionAfter.interestRatePerSecond;
        uint256 protocolInterestRatePerSecondAfter = loanAuctionAfter.protocolInterestRatePerSecond;

        uint256 calculatedInterestRatePerSecond = (uint256(interestRatePerSecondBefore) *
            loanAuctionAfter.amountDrawn) / amountDrawnBefore;
        uint96 calculatedProtocolInterestRatePerSecond = lending.calculateProtocolInterestPerSecond(
            loanAuctionAfter.amountDrawn,
            (loanAuctionAfter.loanEndTimestamp - loanAuctionAfter.loanBeginTimestamp)
        );

        console.log("calculatedInterestRatePerSecond", calculatedInterestRatePerSecond);
        console.log(
            "calculatedProtocolInterestRatePerSecond",
            calculatedProtocolInterestRatePerSecond
        );

        console.log("loanAuctionAfter.loanEndTimestamp", loanAuctionAfter.loanEndTimestamp);
        console.log("loanAuctionAfter.loanBeginTimestamp", loanAuctionAfter.loanBeginTimestamp);

        console.log("loanAuctionAfter.amount", loanAuctionAfter.amount);
        console.log("loanAuctionAfter.amountDrawn", loanAuctionAfter.amountDrawn);

        console.log("interestRatePerSecondAfter", interestRatePerSecondAfter);
        console.log("protocolInterestRatePerSecondAfter", protocolInterestRatePerSecondAfter);

        assertEq(calculatedInterestRatePerSecond, interestRatePerSecondAfter);
        assertEq(calculatedProtocolInterestRatePerSecond, protocolInterestRatePerSecondAfter);
        assertEq(loanAuctionAfter.amountDrawn, amountDrawnBefore + amountExtraOnRefinance);
    }
}
