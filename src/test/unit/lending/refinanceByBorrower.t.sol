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

    function refinanceByLenderSetup(FuzzedOfferFields memory fuzzed, uint16 secondsBeforeRefinance)
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

        defaultFixedOfferFields.creator = lender2;
        fuzzed.duration = fuzzed.duration + 1; // make sure offer is better
        fuzzed.floorTerm = false; // refinance can't be floor term
        fuzzed.expiration = uint32(block.timestamp) + secondsBeforeRefinance + 1;
        fuzzed.amount = offer.amount * 2;

        Offer memory newOffer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        uint256 beforeRefinanceLenderBalance = assetBalance(lender1, address(usdcToken));

        if (offer.asset == address(usdcToken)) {
            beforeRefinanceLenderBalance = assetBalance(lender1, address(usdcToken));
        } else {
            beforeRefinanceLenderBalance = assetBalance(lender1, ETH_ADDRESS);
        }

        (uint256 lenderInterest, uint256 protocolInterest) = lending.calculateInterestAccrued(
            newOffer.nftContractAddress,
            newOffer.nftId
        );

        LoanAuction memory loanAuction = tryToRefinanceByLender(newOffer, "should work");

        assertEq(loanAuction.accumulatedLenderInterest, lenderInterest);
        assertEq(loanAuction.accumulatedProtocolInterest, protocolInterest);
        assertEq(loanAuction.slashableLenderInterest, 0);
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

    function test_unit_refinanceByBorrower_creates_slashable_interest() public {
        // refinance by lender
        refinanceByLenderSetup(defaultFixedFuzzedFieldsForFastUnitTesting, 12 hours);

        // 12 hours
        vm.warp(block.timestamp + 1 hours);

        // set up refinance by borrower
        FuzzedOfferFields memory fuzzed = defaultFixedFuzzedFieldsForFastUnitTesting;

        defaultFixedOfferFields.creator = lender3;
        fuzzed.duration = fuzzed.duration + 1; // make sure offer is better
        fuzzed.floorTerm = false; // refinance can't be floor term
        fuzzed.expiration = uint32(block.timestamp) + 12 hours + 1;
        fuzzed.amount = uint128(
            10 * uint128(10**usdcToken.decimals()) + 10 * uint128(10**usdcToken.decimals())
        );

        Offer memory newOffer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        vm.startPrank(lender3);
        bytes32 offerHash = offers.createOffer(newOffer);
        vm.stopPrank();

        // refinance by borrower
        vm.startPrank(borrower1);
        lending.refinanceByBorrower(
            newOffer.nftContractAddress,
            newOffer.nftId,
            newOffer.floorTerm,
            offerHash,
            lending.getLoanAuction(address(mockNft), 1).lastUpdatedTimestamp
        );
        vm.stopPrank();

        // brand new lender after refinance means slashable should = 0
        assertEq(lending.getLoanAuction(address(mockNft), 1).slashableLenderInterest, 0);
    }

    // At one point (~ Jul 20, 2022) in refinanceByBorrower, slashable interest
    // was being added to what was owed to the protocol, as opposed to what was owed to the lender
    // The following regression test will fail if this bug is present,
    // but pass if it's fixed
    function test_unit_refinanceByBorrower_gives_slashable_interest_to_refinanced_lender() public {
        uint256 beforeLenderBalance = assetBalance(lender2, address(usdcToken));

        // refinance by lender2
        refinanceByLenderSetup(defaultFixedFuzzedFieldsForFastUnitTesting, 12 hours);

        // 12 hours
        vm.warp(block.timestamp + 12 hours);

        // set up refinance by borrower
        FuzzedOfferFields memory fuzzed = defaultFixedFuzzedFieldsForFastUnitTesting;

        defaultFixedOfferFields.creator = lender3;
        fuzzed.duration = fuzzed.duration;
        fuzzed.floorTerm = false; // refinance can't be floor term
        fuzzed.expiration = uint32(block.timestamp) + 12 hours + 1;
        fuzzed.amount = uint128(
            10 * uint128(10**usdcToken.decimals()) + 10 * uint128(10**usdcToken.decimals())
        );

        Offer memory newOffer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        vm.startPrank(lender3);
        bytes32 offerHash = offers.createOffer(newOffer);
        vm.stopPrank();

        uint256 amountDrawn = lending
            .getLoanAuction(newOffer.nftContractAddress, newOffer.nftId)
            .amountDrawn;

        // should be zero but keeping this in in case we convert this to a fuzz test
        uint256 interestShortfall = lending.checkSufficientInterestAccumulated(
            newOffer.nftContractAddress,
            newOffer.nftId
        );

        // refinance by borrower
        vm.startPrank(borrower1);
        lending.refinanceByBorrower(
            newOffer.nftContractAddress,
            newOffer.nftId,
            newOffer.floorTerm,
            offerHash,
            lending.getLoanAuction(address(mockNft), 1).lastUpdatedTimestamp
        );
        vm.stopPrank();

        assertBetween(
            beforeLenderBalance +
                (newOffer.interestRatePerSecond * 12 hours) +
                interestShortfall -
                ((amountDrawn * lending.originationPremiumBps()) / 10_000),
            assetBalance(lender2, address(usdcToken)),
            assetBalancePlusOneCToken(lender2, address(usdcToken))
        );
    }
}
