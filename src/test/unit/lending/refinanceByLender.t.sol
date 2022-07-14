// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";

contract TestRefinanceByLender is Test, OffersLoansRefinancesFixtures {
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

        (uint256 lenderInterest, uint256 protocolInterest) = lending.calculateInterestAccrued(
            newOffer.nftContractAddress,
            newOffer.nftId
        );

        LoanAuction memory loanAuction = tryToRefinanceByLender(newOffer, "should work");

        assertionsForExecutedLenderRefinance(
            offer,
            newOffer,
            loanAuction,
            secondsBeforeRefinance,
            interestShortfall,
            beforeRefinanceLenderBalance
        );
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

    function assertionsForExecutedLenderRefinance(
        Offer memory offer1,
        Offer memory offer2,
        LoanAuction memory loanAuction,
        uint16 secondsBeforeRefinance,
        uint256 interestShortfall,
        uint256 beforeRefinanceLenderBalance
    ) private {
        // lender1 has money
        if (offer2.asset == address(usdcToken)) {
            assertCloseEnough(
                beforeRefinanceLenderBalance +
                    loanAuction.amountDrawn +
                    (offer1.interestRatePerSecond * secondsBeforeRefinance) +
                    interestShortfall +
                    ((loanAuction.amountDrawn * lending.originationPremiumBps()) / 10_000),
                assetBalance(lender1, address(usdcToken)),
                assetBalancePlusOneCToken(lender1, address(usdcToken))
            );
        } else {
            assertCloseEnough(
                beforeRefinanceLenderBalance +
                    loanAuction.amountDrawn +
                    (offer1.interestRatePerSecond * secondsBeforeRefinance) +
                    interestShortfall +
                    ((loanAuction.amountDrawn * lending.originationPremiumBps()) / 10_000),
                assetBalance(lender1, ETH_ADDRESS),
                assetBalancePlusOneCToken(lender1, ETH_ADDRESS)
            );
        }

        // lender2 is now lender
        assertEq(loanAuction.lender, offer2.creator);
        assertEq(loanAuction.loanBeginTimestamp, loanAuction.loanEndTimestamp - offer2.duration);
        assertEq(loanAuction.nftOwner, borrower1);
        assertEq(loanAuction.loanEndTimestamp, loanAuction.loanBeginTimestamp + offer2.duration);
        assertTrue(!loanAuction.fixedTerms);
        assertEq(loanAuction.interestRatePerSecond, offer2.interestRatePerSecond);
        assertEq(loanAuction.asset, offer2.asset);
        assertEq(loanAuction.lenderRefi, true);
        assertEq(loanAuction.amount, offer2.amount);
        assertEq(loanAuction.amountDrawn, offer1.amount);

        uint256 calcProtocolInterestPerSecond = lending.calculateProtocolInterestPerSecond(
            loanAuction.amountDrawn,
            offer1.duration
        );

        assertEq(loanAuction.protocolInterestRatePerSecond, calcProtocolInterestPerSecond);
    }

    function _test_refinanceByLender_simplest_case(
        FuzzedOfferFields memory fuzzed,
        uint16 secondsBeforeRefinance
    ) private {
        refinanceSetup(fuzzed, secondsBeforeRefinance);
    }

    function test_fuzz_refinanceByLender_simplest_case(
        FuzzedOfferFields memory fuzzed,
        uint16 secondsBeforeRefinance,
        uint16 gasGriefingPremiumBps,
        uint16 protocolInterestBps
    ) public validateFuzzedOfferFields(fuzzed) {
        uint256 MAX_FEE = 1_000;
        vm.assume(gasGriefingPremiumBps <= MAX_FEE);
        vm.assume(protocolInterestBps <= MAX_FEE);
        vm.startPrank(owner);
        lending.updateProtocolInterestBps(protocolInterestBps);
        lending.updateGasGriefingPremiumBps(gasGriefingPremiumBps);
        vm.stopPrank();
        _test_refinanceByLender_simplest_case(fuzzed, secondsBeforeRefinance);
    }

    function test_unit_refinanceByLender_simplest_case_usdc() public {
        FuzzedOfferFields memory fixedForSpeed1 = defaultFixedFuzzedFieldsForFastUnitTesting;
        FuzzedOfferFields memory fixedForSpeed2 = defaultFixedFuzzedFieldsForFastUnitTesting;

        fixedForSpeed2.duration += 1 days;
        uint16 secondsBeforeRefinance = 12 hours;

        fixedForSpeed1.randomAsset = 0; // USDC
        fixedForSpeed2.randomAsset = 0; // USDC
        _test_refinanceByLender_simplest_case(fixedForSpeed1, secondsBeforeRefinance);
    }

    function test_unit_refinanceByLender_simplest_slashed() public {
        // Borrower1/Lender1 originate loan
        FuzzedOfferFields memory fuzzed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fuzzed.randomAsset = 0; // USDC
        fuzzed.amount = uint128(1000 * 10**usdcToken.decimals()); // $1000

        uint16 secondsBeforeRefinance = 1 hours;

        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        assertionsForExecutedLoan(offer);

        // 1 hour passes after loan execution
        vm.warp(block.timestamp + 1 hours);

        LoanAuction memory loanAuctionBeforeRefinance = lending.getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );

        uint256 lenderAccruedInterest;
        uint256 protocolAccruedInterest;

        (lenderAccruedInterest, protocolAccruedInterest) = lending.calculateInterestAccrued(
            offer.nftContractAddress,
            offer.nftId
        );
        // should have 1 hour of accrued interest
        assertEq(lenderAccruedInterest, 1 hours * loanAuctionBeforeRefinance.interestRatePerSecond);
        // lenderRefi should be false
        assertEq(loanAuctionBeforeRefinance.lenderRefi, false);

        // set up refinance
        defaultFixedOfferFields.creator = lender2;
        fuzzed.expiration = uint32(block.timestamp) + secondsBeforeRefinance + 1;
        fuzzed.amount = uint128(1000 * 10**usdcToken.decimals() + 1000 * 10**usdcToken.decimals());

        Offer memory newOffer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        tryToRefinanceByLender(newOffer, "should work");

        LoanAuction memory loanAuctionBeforeDraw = lending.getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );

        // 1 hour passes after refinance
        vm.warp(block.timestamp + 1 hours);

        // 1 hour of interest becomes accumulated
        assertEq(
            loanAuctionBeforeDraw.accumulatedLenderInterest,
            1 hours * loanAuctionBeforeDraw.interestRatePerSecond
        );
        // 1 hour of interest accrued
        (lenderAccruedInterest, protocolAccruedInterest) = lending.calculateInterestAccrued(
            offer.nftContractAddress,
            offer.nftId
        );
        assertEq(lenderAccruedInterest, 1 hours * loanAuctionBeforeDraw.interestRatePerSecond);
        // lenderRefi switches to true
        assertEq(loanAuctionBeforeDraw.lenderRefi, true);

        // ensure attempt to draw 1000 USDC overdraws
        vm.startPrank(lender2);
        liquidity.withdrawErc20(address(usdcToken), 500 * 10**usdcToken.decimals());
        vm.stopPrank();

        // borrower attempts to draw 1000 USDC
        vm.startPrank(borrower1);
        lending.drawLoanAmount(
            offer.nftContractAddress,
            offer.nftId,
            1000 * 10**usdcToken.decimals()
        );
        vm.stopPrank();

        LoanAuction memory loanAuctionAfterDraw = lending.getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );

        // 1 hour of interest still accumulated
        assertEq(
            loanAuctionAfterDraw.accumulatedLenderInterest,
            1 hours * loanAuctionBeforeDraw.interestRatePerSecond
        );
        // slashable is 0
        assertEq(loanAuctionAfterDraw.slashableLenderInterest, 0);
        (lenderAccruedInterest, protocolAccruedInterest) = lending.calculateInterestAccrued(
            offer.nftContractAddress,
            offer.nftId
        );
        // 1 hour of interest accrued has been slashed
        // (in drawLoanAmount, this gets turned into slashable in _updateInterest,
        // and slashable gets set to 0 in _slashUnsupportedAmount)
        assertEq(lenderAccruedInterest, 0);
        // lenderRefi toggled back to false
        assertEq(loanAuctionAfterDraw.lenderRefi, false);

        // 1 hour passes after draw and slash
        vm.warp(block.timestamp + 1 hours);

        // 1 hour of interest still accumulated
        assertEq(
            loanAuctionAfterDraw.accumulatedLenderInterest,
            1 hours * loanAuctionBeforeDraw.interestRatePerSecond
        );
        // slashable 0
        assertEq(loanAuctionAfterDraw.slashableLenderInterest, 0);
        // lenderRefi still false
        assertEq(loanAuctionAfterDraw.lenderRefi, false);
        // but 1 hour of accrued interest
        (lenderAccruedInterest, protocolAccruedInterest) = lending.calculateInterestAccrued(
            offer.nftContractAddress,
            offer.nftId
        );
        assertEq(lenderAccruedInterest, 1 hours * loanAuctionAfterDraw.interestRatePerSecond);

        // set up borrower repay full amount
        vm.startPrank(borrower1);
        mintUsdc(borrower1, ~uint128(0));
        usdcToken.increaseAllowance(address(liquidity), ~uint256(0));

        // most important part here is the amount repaid, the last argument to the event
        // the amount drawn + 1 hour at initial interest rate + 1 hour at "after draw" interest rate
        // even though the borrower couldn't draw 1000 USDC, they could draw some, so the rate changes
        vm.expectEmit(true, true, true, true);
        emit LoanRepaid(
            loanAuctionAfterDraw.lender,
            loanAuctionAfterDraw.nftOwner,
            offer.nftContractAddress,
            offer.nftId,
            loanAuctionAfterDraw.asset,
            loanAuctionAfterDraw.amountDrawn +
                1 hours *
                loanAuctionBeforeDraw.interestRatePerSecond +
                1 hours *
                loanAuctionAfterDraw.interestRatePerSecond
        );

        lending.repayLoan(offer.nftContractAddress, offer.nftId);
        vm.stopPrank();

        // check borrower balance
        assertEq(assetBalance(borrower1, address(usdcToken)), 0);

        // check lender balance
        assertEq(
            assetBalance(lender2, address(usdcToken)),
            loanAuctionAfterDraw.amountDrawn +
                1 hours *
                loanAuctionBeforeDraw.interestRatePerSecond +
                1 hours *
                loanAuctionAfterDraw.interestRatePerSecond
        );
    }

    // function test_unit_refinanceByLender_simplest_case_eth() public {
    //     FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
    //     fixedForSpeed.randomAsset = 1; // ETH
    //     _test_refinanceByLender_simplest_case(fixedForSpeed);
    // }

    // function _test_refinanceByLender_events(FuzzedOfferFields memory fuzzed) private {
    //     Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

    //     vm.expectEmit(true, true, true, true);
    //     emit LoanExecuted(offer.nftContractAddress, offer.nftId, offer);

    //     createOfferAndTryToExecuteLoanByBorrower(offer, "should work");
    // }

    // function test_unit_refinanceByLender_events() public {
    //     _test_refinanceByLender_events(defaultFixedFuzzedFieldsForFastUnitTesting);
    // }

    // function test_fuzz_refinanceByLender_events(FuzzedOfferFields memory fuzzed)
    //     public
    //     validateFuzzedOfferFields(fuzzed)
    // {
    //     _test_refinanceByLender_events(fuzzed);
    // }

    // function _test_cannot_refinanceByLender_if_offer_expired(FuzzedOfferFields memory fuzzed)
    //     private
    // {
    //     Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
    //     createOffer(offer);
    //     vm.warp(offer.expiration);
    //     approveLending(offer);
    //     tryToExecuteLoanByBorrower(offer, "00010");
    // }

    // function test_fuzz_cannot_refinanceByLender_if_offer_expired(
    //     FuzzedOfferFields memory fuzzed
    // ) public validateFuzzedOfferFields(fuzzed) {
    //     _test_cannot_refinanceByLender_if_offer_expired(fuzzed);
    // }

    // function test_unit_cannot_refinanceByLender_if_offer_expired() public {
    //     _test_cannot_refinanceByLender_if_offer_expired(
    //         defaultFixedFuzzedFieldsForFastUnitTesting
    //     );
    // }

    // function _test_cannot_refinanceByLender_if_asset_not_in_allow_list(
    //     FuzzedOfferFields memory fuzzed
    // ) public {
    //     Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
    //     createOffer(offer);
    //     vm.startPrank(owner);
    //     liquidity.setCAssetAddress(offer.asset, address(0));
    //     vm.stopPrank();
    //     tryToExecuteLoanByBorrower(offer, "00040");
    // }

    // function test_fuzz_cannot_refinanceByLender_if_asset_not_in_allow_list(
    //     FuzzedOfferFields memory fuzzed
    // ) public validateFuzzedOfferFields(fuzzed) {
    //     _test_cannot_refinanceByLender_if_asset_not_in_allow_list(fuzzed);
    // }

    // function test_unit_cannot_refinanceByLender_if_asset_not_in_allow_list() public {
    //     _test_cannot_refinanceByLender_if_asset_not_in_allow_list(
    //         defaultFixedFuzzedFieldsForFastUnitTesting
    //     );
    // }

    // function _test_cannot_refinanceByLender_if_offer_not_created(
    //     FuzzedOfferFields memory fuzzed
    // ) private {
    //     Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
    //     // notice conspicuous absence of createOffer here
    //     approveLending(offer);
    //     tryToExecuteLoanByBorrower(offer, "00012");
    // }

    // function test_fuzz_cannot_refinanceByLender_if_offer_not_created(
    //     FuzzedOfferFields memory fuzzed
    // ) public validateFuzzedOfferFields(fuzzed) {
    //     _test_cannot_refinanceByLender_if_offer_not_created(fuzzed);
    // }

    // function test_unit_cannot_refinanceByLender_if_offer_not_created() public {
    //     _test_cannot_refinanceByLender_if_offer_not_created(
    //         defaultFixedFuzzedFieldsForFastUnitTesting
    //     );
    // }

    // function _test_cannot_refinanceByLender_if_dont_own_nft(FuzzedOfferFields memory fuzzed)
    //     private
    // {
    //     Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
    //     createOffer(offer);
    //     approveLending(offer);
    //     vm.startPrank(borrower1);
    //     mockNft.safeTransferFrom(borrower1, borrower2, 1);
    //     vm.stopPrank();
    //     tryToExecuteLoanByBorrower(offer, "00018");
    // }

    // function test_fuzz_cannot_refinanceByLender_if_dont_own_nft(FuzzedOfferFields memory fuzzed)
    //     public
    //     validateFuzzedOfferFields(fuzzed)
    // {
    //     _test_cannot_refinanceByLender_if_dont_own_nft(fuzzed);
    // }

    // function test_unit_cannot_refinanceByLender_if_dont_own_nft() public {
    //     _test_cannot_refinanceByLender_if_dont_own_nft(
    //         defaultFixedFuzzedFieldsForFastUnitTesting
    //     );
    // }

    // function _test_cannot_refinanceByLender_if_not_enough_tokens(
    //     FuzzedOfferFields memory fuzzed
    // ) private {
    //     Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
    //     createOffer(offer);
    //     approveLending(offer);

    //     vm.startPrank(lender1);
    //     if (offer.asset == address(usdcToken)) {
    //         liquidity.withdrawErc20(address(usdcToken), defaultUsdcLiquiditySupplied);
    //     } else {
    //         liquidity.withdrawEth(defaultEthLiquiditySupplied);
    //     }
    //     vm.stopPrank();

    //     tryToExecuteLoanByBorrower(offer, "00034");
    // }

    // function test_fuzz_cannot_refinanceByLender_if_not_enough_tokens(
    //     FuzzedOfferFields memory fuzzed
    // ) public validateFuzzedOfferFields(fuzzed) {
    //     _test_cannot_refinanceByLender_if_not_enough_tokens(fuzzed);
    // }

    // function test_unit_cannot_refinanceByLender_if_not_enough_tokens() public {
    //     _test_cannot_refinanceByLender_if_not_enough_tokens(
    //         defaultFixedFuzzedFieldsForFastUnitTesting
    //     );
    // }

    // function _test_cannot_refinanceByLender_if_underlying_transfer_fails(
    //     FuzzedOfferFields memory fuzzed
    // ) private {
    //     // Can only be mocked
    //     bool integration = false;
    //     try vm.envBool("INTEGRATION") returns (bool isIntegration) {
    //         integration = isIntegration;
    //     } catch (bytes memory) {
    //         // This catches revert that occurs if env variable not supplied
    //     }

    //     if (!integration) {
    //         fuzzed.randomAsset = 0; // USDC
    //         Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
    //         usdcToken.setTransferFail(true);
    //         createOfferAndTryToExecuteLoanByBorrower(
    //             offer,
    //             "SafeERC20: ERC20 operation did not succeed"
    //         );
    //     }
    // }

    // function test_fuzz_cannot_refinanceByLender_if_underlying_transfer_fails(
    //     FuzzedOfferFields memory fuzzed
    // ) public validateFuzzedOfferFields(fuzzed) {
    //     _test_cannot_refinanceByLender_if_underlying_transfer_fails(fuzzed);
    // }

    // function test_unit_cannot_refinanceByLender_if_underlying_transfer_fails() public {
    //     _test_cannot_refinanceByLender_if_underlying_transfer_fails(
    //         defaultFixedFuzzedFieldsForFastUnitTesting
    //     );
    // }

    // function _test_cannot_refinanceByLender_if_eth_transfer_fails(
    //     FuzzedOfferFields memory fuzzed
    // ) private {
    //     fuzzed.randomAsset = 1; // ETH
    //     Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

    //     // give NFT to contract
    //     vm.startPrank(borrower1);
    //     mockNft.safeTransferFrom(borrower1, address(contractThatCannotReceiveEth), 1);
    //     vm.stopPrank();

    //     // set borrower1 to contract
    //     borrower1 = payable(address(contractThatCannotReceiveEth));

    //     createOfferAndTryToExecuteLoanByBorrower(
    //         offer,
    //         "Address: unable to send value, recipient may have reverted"
    //     );
    // }

    // function test_fuzz_cannot_refinanceByLender_if_eth_transfer_fails(
    //     FuzzedOfferFields memory fuzzed
    // ) public validateFuzzedOfferFields(fuzzed) {
    //     _test_cannot_refinanceByLender_if_eth_transfer_fails(fuzzed);
    // }

    // function test_unit_cannot_refinanceByLender_if_eth_transfer_fails() public {
    //     _test_cannot_refinanceByLender_if_eth_transfer_fails(
    //         defaultFixedFuzzedFieldsForFastUnitTesting
    //     );
    // }

    // function _test_cannot_refinanceByLender_if_borrower_offer(FuzzedOfferFields memory fuzzed)
    //     private
    // {
    //     defaultFixedOfferFields.lenderOffer = false;
    //     fuzzed.floorTerm = false; // borrower can't make a floor term offer

    //     Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

    //     // pass NFT to lender1 so they can make a borrower offer
    //     vm.startPrank(borrower1);
    //     mockNft.safeTransferFrom(borrower1, lender1, 1);
    //     vm.stopPrank();

    //     createOffer(offer);

    //     // pass NFT back to borrower1 so they can try to execute a borrower offer
    //     vm.startPrank(lender1);
    //     mockNft.safeTransferFrom(lender1, borrower1, 1);
    //     vm.stopPrank();

    //     approveLending(offer);
    //     tryToExecuteLoanByBorrower(offer, "00012");
    // }

    // function test_fuzz_refinanceByLender_if_borrower_offer(FuzzedOfferFields memory fuzzed)
    //     public
    //     validateFuzzedOfferFields(fuzzed)
    // {
    //     _test_cannot_refinanceByLender_if_borrower_offer(fuzzed);
    // }

    // function test_unit_refinanceByLender_if_borrower_offer() public {
    //     _test_cannot_refinanceByLender_if_borrower_offer(
    //         defaultFixedFuzzedFieldsForFastUnitTesting
    //     );
    // }

    // function _test_cannot_refinanceByLender_if_loan_active(FuzzedOfferFields memory fuzzed)
    //     private
    // {
    //     defaultFixedOfferFields.lenderOffer = true;
    //     fuzzed.floorTerm = true;

    //     Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

    //     createOffer(offer);

    //     approveLending(offer);
    //     tryToExecuteLoanByBorrower(offer, "should work");

    //     tryToExecuteLoanByBorrower(offer, "00006");
    // }

    // function test_fuzz_refinanceByLender_if_loan_active(FuzzedOfferFields memory fuzzed)
    //     public
    //     validateFuzzedOfferFields(fuzzed)
    // {
    //     _test_cannot_refinanceByLender_if_loan_active(fuzzed);
    // }

    // function test_unit_refinanceByLender_if_loan_active() public {
    //     _test_cannot_refinanceByLender_if_loan_active(
    //         defaultFixedFuzzedFieldsForFastUnitTesting
    //     );
    // }
}
