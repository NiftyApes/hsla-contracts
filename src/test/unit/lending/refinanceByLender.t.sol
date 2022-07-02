// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

// contract ContractThatCannotReceiveEth is ERC721HolderUpgradeable {
//     receive() external payable {
//         revert("no Eth!");
//     }
// }

contract TestRefinanceByLender is Test, OffersLoansRefinancesFixtures {
    // ContractThatCannotReceiveEth private contractThatCannotReceiveEth;

    function setUp() public override {
        super.setUp();

        // contractThatCannotReceiveEth = new ContractThatCannotReceiveEth();
    }

    function assertionsForRefinancedLoan(
        Offer memory offer1,
        Offer memory offer2,
        LoanAuction memory loanAuction
    ) private {
        // borrower has money
        if (offer1.asset == address(usdcToken)) {
            assertEq(usdcToken.balanceOf(borrower1), offer1.amount);
        } else {
            assertEq(borrower1.balance, defaultInitialEthBalance + offer1.amount);
        }
        // lending contract has NFT
        assertEq(mockNft.ownerOf(1), address(lending));
        // loan auction exists
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.lender, offer2.creator);

        console.log("nftOwner", loanAuction.nftOwner);
        console.log("loanEndTimestamp", loanAuction.loanEndTimestamp);
        console.log("lastUpdatedTimestamp", loanAuction.lastUpdatedTimestamp);
        console.log("fixedTerms", loanAuction.fixedTerms);
        console.log("lender", loanAuction.lender);
        console.log("interestRatePerSecond", loanAuction.interestRatePerSecond);
        console.log("asset", loanAuction.asset);
        console.log("loanBeginTimestamp", loanAuction.loanBeginTimestamp);
        console.log("lenderRefi", loanAuction.lenderRefi);
        console.log("accumulatedLenderInterest", loanAuction.accumulatedLenderInterest);
        console.log("accumulatedProtocolInterest", loanAuction.accumulatedProtocolInterest);
        console.log("amount", loanAuction.amount);
        console.log("amountDrawn", loanAuction.amountDrawn);
        console.log("protocolInterestRatePerSecond", loanAuction.protocolInterestRatePerSecond);
        console.log("slashableLenderInterest", loanAuction.slashableLenderInterest);

        assertEq(loanAuction.loanBeginTimestamp, loanAuction.loanEndTimestamp - offer2.duration);
        assertEq(loanAuction.lender, offer2.creator);
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

        console.log("calcProtocolInterestPerSecond", calcProtocolInterestPerSecond);

        assertEq(loanAuction.protocolInterestRatePerSecond, calcProtocolInterestPerSecond);
    }

    function _test_refinanceByLender_simplest_case(
        FuzzedOfferFields memory fuzzed,
        uint16 secondsBeforeRefinance
    ) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

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

        (uint256 lenderInterest, uint256 protocolInterest) = lending.calculateInterestAccrued(
            newOffer.nftContractAddress,
            newOffer.nftId
        );

        LoanAuction memory loanAuction = tryToRefinanceByLender(newOffer, "should work");

        assertionsForRefinancedLoan(offer, newOffer, loanAuction);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, protocolInterest);
        assertEq(loanAuction.slashableLenderInterest, lenderInterest);
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
