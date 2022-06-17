// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/LenderLiquidityFixtures.sol";

import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";

contract TestExecuteLoanByBorrower is Test, IOffersStructs, LenderLiquidityFixtures {
    struct FuzzedOfferFields {
        bool fixedTerms;
        bool floorTerm;
        uint128 amount;
        uint96 interestRatePerSecond;
        uint32 duration;
        uint32 expiration;
    }

    struct FixedOfferFields {
        address creator;
        bool lenderOffer;
        uint256 nftId;
        address nftContractAddress;
        address asset;
    }

    FixedOfferFields internal fixedOfferFields;

    function setUp() public override {
        super.setUp();

        // NOTE HOW creator THIS WAS UNASSIGNED ABOVE
        fixedOfferFields = FixedOfferFields({
            creator: lender1,
            lenderOffer: true,
            nftContractAddress: address(mockNft),
            nftId: 1,
            asset: address(usdcToken)
        });
    }

    modifier validateFuzzedOfferFields(FuzzedOfferFields memory fuzzed) {
        vm.assume(fuzzed.amount > 0);
        vm.assume(fuzzed.amount < 1000 ether);
        vm.assume(fuzzed.duration > 1 days);
        // to avoid overflow when loanAuction.loanEndTimestamp = _currentTimestamp32() + offer.duration;
        vm.assume(fuzzed.duration < ~uint32(0) - block.timestamp);
        vm.assume(fuzzed.expiration > block.timestamp);
        _;
    }

    function fieldsToOffer(FuzzedOfferFields memory fuzzed, FixedOfferFields memory fixedFields)
        private
        returns (Offer memory)
    {
        return
            Offer({
                creator: fixedFields.creator,
                lenderOffer: fixedFields.lenderOffer,
                nftId: fixedFields.nftId,
                nftContractAddress: fixedFields.nftContractAddress,
                asset: fixedFields.asset,
                fixedTerms: fuzzed.fixedTerms,
                floorTerm: fuzzed.floorTerm,
                interestRatePerSecond: fuzzed.interestRatePerSecond,
                amount: fuzzed.amount,
                duration: fuzzed.duration,
                expiration: fuzzed.expiration
            });
    }

    function assertionsForExecutedLoan(Offer memory offer) public {
        // borrower has money
        assertEq(usdcToken.balanceOf(borrower1), offer.amount);
        // lending contract has NFT
        assertEq(mockNft.ownerOf(1), address(lending));
        // loan auction exists
        assertEq(lending.getLoanAuction(address(mockNft), 1).lastUpdatedTimestamp, block.timestamp);
    }

    function createOffer(Offer memory offer) public {
        vm.prank(lender1);
        offers.createOffer(offer);
    }

    function approveLending(Offer memory offer) public {
        vm.prank(borrower1);
        mockNft.approve(address(lending), offer.nftId);
    }

    function tryToExecuteLoanByBorrower(Offer memory offer, bytes memory errorCode) public {
        vm.startPrank(borrower1);
        bytes32 offerHash = offers.getOfferHash(offer);

        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }

        lending.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
        vm.stopPrank();
    }

    function createOfferAndTryToExecuteLoanByBorrower(Offer memory offer, bytes memory errorCode)
        public
    {
        createOffer(offer);
        approveLending(offer);
        tryToExecuteLoanByBorrower(offer, errorCode);
    }

    function testExecuteLoanByBorrower_works_moose(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        Offer memory offer = fieldsToOffer(fuzzed, fixedOfferFields);
        tryToExecuteLoanByBorrower(offer, "should work");
        assertionsForExecutedLoan(offer);
    }

    function testCannotExecuteLoanByBorrower_if_offer_expired(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        Offer memory offer = fieldsToOffer(fuzzed, fixedOfferFields);
        createOffer(offer);
        vm.warp(offer.expiration);
        approveLending(offer);
        tryToExecuteLoanByBorrower(offer, "00010");
    }

    function testCannotExecuteLoanByBorrower_if_offer_duration_too_short(
        FuzzedOfferFields memory fuzzedOfferFields
    ) public validateFuzzedOfferFields(fuzzedOfferFields) {
        fuzzedOfferFields.duration = 1 days - 1;
        Offer memory offer = fieldsToOffer(fuzzedOfferFields, fixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "00011");
    }

    function testCannotExecuteLoanByBorrower_if_asset_not_in_allow_list(
        FuzzedOfferFields memory fuzzedOfferFields
    ) public validateFuzzedOfferFields(fuzzedOfferFields) {
        Offer memory offer = fieldsToOffer(fuzzedOfferFields, fixedOfferFields);
        createOffer(offer);
        vm.prank(owner);
        liquidity.setCAssetAddress(address(usdcToken), address(0));
        tryToExecuteLoanByBorrower(offer, "00040");
    }

    function testCannotExecuteLoanByBorrower_if_offer_not_created(
        FuzzedOfferFields memory fuzzedOfferFields
    ) public validateFuzzedOfferFields(fuzzedOfferFields) {
        Offer memory offer = fieldsToOffer(fuzzedOfferFields, fixedOfferFields);
        approveLending(offer);
        tryToExecuteLoanByBorrower(offer, "00012");
    }

    function testCannotExecuteLoanByBorrower_if_not_own_nft(
        FuzzedOfferFields memory fuzzedOfferFields
    ) public validateFuzzedOfferFields(fuzzedOfferFields) {
        Offer memory offer = fieldsToOffer(fuzzedOfferFields, fixedOfferFields);
        vm.prank(borrower1);
        mockNft.safeTransferFrom(borrower1, borrower2, 1);
        createOfferAndTryToExecuteLoanByBorrower(offer, "00018");
    }

    function testCannotExecuteLoanByBorrower_not_enough_tokens(
        FuzzedOfferFields memory fuzzedOfferFields
    ) public validateFuzzedOfferFields(fuzzedOfferFields) {
        Offer memory offer = fieldsToOffer(fuzzedOfferFields, fixedOfferFields);
        createOffer(offer);
        approveLending(offer);
        vm.prank(lender1);
        liquidity.withdrawErc20(address(usdcToken), 1000 ether);
        tryToExecuteLoanByBorrower(offer, "00034");
    }
}
