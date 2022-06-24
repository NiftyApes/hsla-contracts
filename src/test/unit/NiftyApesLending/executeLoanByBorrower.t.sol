// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract ContractThatCannotReceiveEth is ERC721HolderUpgradeable {
    receive() external payable {
        revert("no Eth!");
    }
}

contract TestExecuteLoanByBorrower is Test, OffersLoansRefinancesFixtures {
    ContractThatCannotReceiveEth private contractThatCannotReceiveEth;

    function setUp() public override {
        super.setUp();

        contractThatCannotReceiveEth = new ContractThatCannotReceiveEth();
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

    function _test_executeLoanByBorrower_simplest_case(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");
        assertionsForExecutedLoan(offer);
    }

    function test_fuzz_executeLoanByBorrower_simplest_case(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        _test_executeLoanByBorrower_simplest_case(fuzzed);
    }

    function test_unit_executeLoanByBorrower_simplest_case_usdc() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0; // USDC
        _test_executeLoanByBorrower_simplest_case(fixedForSpeed);
    }

    function test_unit_executeLoanByBorrower_simplest_case_eth() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1; // ETH
        _test_executeLoanByBorrower_simplest_case(fixedForSpeed);
    }

    function _test_executeLoanByBorrower_events(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        vm.expectEmit(true, true, true, true);
        emit LoanExecuted(offer.nftContractAddress, offer.nftId, offer);

        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");
    }

    function test_unit_executeLoanByBorrower_events() public {
        _test_executeLoanByBorrower_events(defaultFixedFuzzedFieldsForFastUnitTesting);
    }

    function test_fuzz_executeLoanByBorrower_events(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        _test_executeLoanByBorrower_events(fuzzed);
    }

    function _test_cannot_executeLoanByBorrower_if_offer_expired(FuzzedOfferFields memory fuzzed)
        private
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOffer(offer);
        vm.warp(offer.expiration);
        approveLending(offer);
        tryToExecuteLoanByBorrower(offer, "00010");
    }

    function test_fuzz_cannot_executeLoanByBorrower_if_offer_expired(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        _test_cannot_executeLoanByBorrower_if_offer_expired(fuzzed);
    }

    function test_unit_cannot_executeLoanByBorrower_if_offer_expired() public {
        _test_cannot_executeLoanByBorrower_if_offer_expired(
            defaultFixedFuzzedFieldsForFastUnitTesting
        );
    }

    function _test_cannot_executeLoanByBorrower_if_asset_not_in_allow_list(
        FuzzedOfferFields memory fuzzed
    ) public {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOffer(offer);
        vm.startPrank(owner);
        liquidity.setCAssetAddress(offer.asset, address(0));
        vm.stopPrank();
        tryToExecuteLoanByBorrower(offer, "00040");
    }

    function test_fuzz_cannot_executeLoanByBorrower_if_asset_not_in_allow_list(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        _test_cannot_executeLoanByBorrower_if_asset_not_in_allow_list(fuzzed);
    }

    function test_unit_cannot_executeLoanByBorrower_if_asset_not_in_allow_list() public {
        _test_cannot_executeLoanByBorrower_if_asset_not_in_allow_list(
            defaultFixedFuzzedFieldsForFastUnitTesting
        );
    }

    function _test_cannot_executeLoanByBorrower_if_offer_not_created(
        FuzzedOfferFields memory fuzzed
    ) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        // notice conspicuous absence of createOffer here
        approveLending(offer);
        tryToExecuteLoanByBorrower(offer, "00012");
    }

    function test_fuzz_cannot_executeLoanByBorrower_if_offer_not_created(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        _test_cannot_executeLoanByBorrower_if_offer_not_created(fuzzed);
    }

    function test_unit_cannot_executeLoanByBorrower_if_offer_not_created() public {
        _test_cannot_executeLoanByBorrower_if_offer_not_created(
            defaultFixedFuzzedFieldsForFastUnitTesting
        );
    }

    function _test_cannot_executeLoanByBorrower_if_dont_own_nft(FuzzedOfferFields memory fuzzed)
        private
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOffer(offer);
        approveLending(offer);
        vm.startPrank(borrower1);
        mockNft.safeTransferFrom(borrower1, borrower2, 1);
        vm.stopPrank();
        tryToExecuteLoanByBorrower(offer, "00018");
    }

    function test_fuzz_cannot_executeLoanByBorrower_if_dont_own_nft(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        _test_cannot_executeLoanByBorrower_if_dont_own_nft(fuzzed);
    }

    function test_unit_cannot_executeLoanByBorrower_if_dont_own_nft() public {
        _test_cannot_executeLoanByBorrower_if_dont_own_nft(
            defaultFixedFuzzedFieldsForFastUnitTesting
        );
    }

    function _test_cannot_executeLoanByBorrower_if_not_enough_tokens(
        FuzzedOfferFields memory fuzzed
    ) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOffer(offer);
        approveLending(offer);

        vm.startPrank(lender1);
        if (offer.asset == address(usdcToken)) {
            liquidity.withdrawErc20(address(usdcToken), defaultUsdcLiquiditySupplied);
        } else {
            liquidity.withdrawEth(defaultEthLiquiditySupplied);
        }
        vm.stopPrank();

        tryToExecuteLoanByBorrower(offer, "00034");
    }

    function test_fuzz_cannot_executeLoanByBorrower_if_not_enough_tokens(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        _test_cannot_executeLoanByBorrower_if_not_enough_tokens(fuzzed);
    }

    function test_unit_cannot_executeLoanByBorrower_if_not_enough_tokens() public {
        _test_cannot_executeLoanByBorrower_if_not_enough_tokens(
            defaultFixedFuzzedFieldsForFastUnitTesting
        );
    }

    function _test_cannot_executeLoanByBorrower_if_underlying_transfer_fails(
        FuzzedOfferFields memory fuzzed
    ) private {
        // Can only be mocked
        bool integration = false;
        try vm.envBool("INTEGRATION") returns (bool isIntegration) {
            integration = isIntegration;
        } catch (bytes memory) {
            // This catches revert that occurs if env variable not supplied
        }

        if (!integration) {
            fuzzed.randomAsset = 0; // USDC
            Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
            usdcToken.setTransferFail(true);
            createOfferAndTryToExecuteLoanByBorrower(
                offer,
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }

    function test_fuzz_cannot_executeLoanByBorrower_if_underlying_transfer_fails(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        _test_cannot_executeLoanByBorrower_if_underlying_transfer_fails(fuzzed);
    }

    function test_unit_cannot_executeLoanByBorrower_if_underlying_transfer_fails() public {
        _test_cannot_executeLoanByBorrower_if_underlying_transfer_fails(
            defaultFixedFuzzedFieldsForFastUnitTesting
        );
    }

    function _test_cannot_executeLoanByBorrower_if_eth_transfer_fails(
        FuzzedOfferFields memory fuzzed
    ) private {
        fuzzed.randomAsset = 1; // ETH
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        // give NFT to contract
        vm.startPrank(borrower1);
        mockNft.safeTransferFrom(borrower1, address(contractThatCannotReceiveEth), 1);
        vm.stopPrank();

        // set borrower1 to contract
        borrower1 = payable(address(contractThatCannotReceiveEth));

        createOfferAndTryToExecuteLoanByBorrower(
            offer,
            "Address: unable to send value, recipient may have reverted"
        );
    }

    function test_fuzz_cannot_executeLoanByBorrower_if_eth_transfer_fails(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        _test_cannot_executeLoanByBorrower_if_eth_transfer_fails(fuzzed);
    }

    function test_unit_cannot_executeLoanByBorrower_if_eth_transfer_fails() public {
        _test_cannot_executeLoanByBorrower_if_eth_transfer_fails(
            defaultFixedFuzzedFieldsForFastUnitTesting
        );
    }

    function _test_cannot_executeLoanByBorrower_if_borrower_offer(FuzzedOfferFields memory fuzzed)
        private
    {
        defaultFixedOfferFields.lenderOffer = false;
        fuzzed.floorTerm = false; // borrower can't make a floor term offer

        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        // pass NFT to lender1 so they can make a borrower offer
        vm.startPrank(borrower1);
        mockNft.safeTransferFrom(borrower1, lender1, 1);
        vm.stopPrank();

        createOffer(offer);

        // pass NFT back to borrower1 so they can try to execute a borrower offer
        vm.startPrank(lender1);
        mockNft.safeTransferFrom(lender1, borrower1, 1);
        vm.stopPrank();

        approveLending(offer);
        tryToExecuteLoanByBorrower(offer, "00012");
    }

    function test_fuzz_executeLoanByBorrower_if_borrower_offer(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        _test_cannot_executeLoanByBorrower_if_borrower_offer(fuzzed);
    }

    function test_unit_executeLoanByBorrower_if_borrower_offer() public {
        _test_cannot_executeLoanByBorrower_if_borrower_offer(
            defaultFixedFuzzedFieldsForFastUnitTesting
        );
    }
}
