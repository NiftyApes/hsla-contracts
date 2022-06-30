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

    function assertionsForRefinancedLoan(Offer memory offer, LoanAuction memory loanAuction)
        private
    {
        // lending contract has NFT
        assertEq(mockNft.ownerOf(1), address(lending));
        // loan auction exists
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.lender, offer.creator);

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

        assertEq(loanAuction.loanBeginTimestamp, loanAuction.loanEndTimestamp - offer.duration);
        assertEq(loanAuction.lender, offer.creator);
        assertEq(loanAuction.nftOwner, borrower1);
        assertEq(loanAuction.loanEndTimestamp, loanAuction.loanBeginTimestamp + offer.duration);
        assertTrue(!loanAuction.fixedTerms);
        assertEq(loanAuction.interestRatePerSecond, offer.interestRatePerSecond);
        assertEq(loanAuction.asset, offer.asset);
        assertEq(loanAuction.lenderRefi, true);

        // assertEq(loanAuction.amount, 7 ether);
        // assertEq(loanAuction.amountDrawn, 6 ether);
        // assertEq(loanAuction.protocolInterestRatePerSecond, 6 ether);
        // assertEq(loanAuction.slashableLenderInterest, 6 ether);
    }

    function _test_refinanceByLender_simplest_case(
        FuzzedOfferFields memory fuzzed1,
        FuzzedOfferFields memory fuzzed2
    ) private {
        Offer memory offer1 = offerStructFromFields(fuzzed1, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer1, "should work");

        vm.warp(block.timestamp + 12 hours);

        Offer memory offer2 = offerStructFromFields(fuzzed2, defaultFixedOfferFields);

        (uint256 lenderInterest, uint256 protocolInterest) = lending.calculateInterestAccrued(
            offer2.nftContractAddress,
            offer2.nftId
        );

        console.log("lenderInterest", lenderInterest);
        console.log("protocolInterest", protocolInterest);

        (, LoanAuction memory loanAuction) = createOfferAndTryToRefinanceByLender(
            offer2,
            "should work"
        );

        assertionsForRefinancedLoan(offer2, loanAuction);
        assertEq(loanAuction.accumulatedLenderInterest, lenderInterest);
        assertEq(loanAuction.accumulatedProtocolInterest, protocolInterest);
    }

    function test_fuzz_refinanceByLender_simplest_case(
        FuzzedOfferFields memory fuzzed1,
        FuzzedOfferFields memory fuzzed2
    ) public validateFuzzedOfferFields(fuzzed1) {
        _test_refinanceByLender_simplest_case(fuzzed1, fuzzed2);
    }

    function test_unit_refinanceByLender_simplest_case_usdc() public {
        FuzzedOfferFields memory fixedForSpeed1 = defaultFixedFuzzedFieldsForFastUnitTesting;
        FuzzedOfferFields memory fixedForSpeed2 = defaultFixedFuzzedFieldsForFastUnitTesting;

        fixedForSpeed2.duration += 1 days;

        fixedForSpeed1.randomAsset = 0; // USDC
        fixedForSpeed2.randomAsset = 0; // USDC
        _test_refinanceByLender_simplest_case(fixedForSpeed1, fixedForSpeed2);
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
