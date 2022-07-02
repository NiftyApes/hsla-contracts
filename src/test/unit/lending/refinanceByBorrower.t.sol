// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";

contract TestExecuteLoanByBorrower is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function refinanceSetup(FuzzedOfferFields memory fuzzed, uint16 secondsBeforeRefinance)
        private
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        assertionsForExecutedLoan(offer);

        uint256 amountDrawn = lending
            .getLoanAuction(offer.nftContractAddress, offer.nftId)
            .amountDrawn;

        vm.warp(block.timestamp + secondsBeforeRefinance);

        uint256 interestShortfall = lending.checkSufficientInterestAccumulated(
            offer.nftContractAddress,
            offer.nftId
        );

        // will trigger gas griefing (but not term griefing with borrower refinance)
        defaultFixedOfferFields.creator = lender2;
        fuzzed.duration = fuzzed.duration + 1; // make sure offer is better
        fuzzed.floorTerm = false; // refinance can't be floor term
        fuzzed.expiration = uint32(block.timestamp) + secondsBeforeRefinance + 1;
        fuzzed.amount = uint128(
            offer.amount +
                (offer.interestRatePerSecond * secondsBeforeRefinance) +
                interestShortfall +
                ((amountDrawn * lending.protocolInterestBps()) / 10_000)
        );

        Offer memory newOffer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        uint256 beforeRefinanceLenderBalance = assetBalance(lender1, address(usdcToken));

        if (offer.asset == address(usdcToken)) {
            beforeRefinanceLenderBalance = assetBalance(lender1, address(usdcToken));
        } else {
            beforeRefinanceLenderBalance = assetBalance(lender1, ETH_ADDRESS);
        }

        tryToRefinanceLoanByBorrower(newOffer, "should work");

        assertionsForExecutedRefinance(
            offer,
            amountDrawn,
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

    function test_fuzz_refinanceByBorrower(
        FuzzedOfferFields memory fuzzedOffer,
        uint16 secondsBeforeRefinance,
        uint16 gasGriefingPremiumBps,
        uint16 protocolInterestBps
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        uint256 MAX_FEE = 1_000;
        vm.assume(gasGriefingPremiumBps <= MAX_FEE);
        vm.assume(protocolInterestBps <= MAX_FEE);
        vm.startPrank(owner);
        lending.updateProtocolInterestBps(protocolInterestBps);
        lending.updateGasGriefingPremiumBps(gasGriefingPremiumBps);
        vm.stopPrank();
        refinanceSetup(fuzzedOffer, secondsBeforeRefinance);
    }
}
