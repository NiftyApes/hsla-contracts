// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersEvents.sol";

contract TestRefinanceLoanByBorrowerSignature is
    Test,
    OffersLoansRefinancesFixtures,
    IOffersEvents
{
    function setUp() public override {
        super.setUp();
    }

    function sign(uint256 signerPrivateKey, bytes32 digest) internal returns (bytes memory) {
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = vm.sign(signerPrivateKey, digest);

        bytes memory signature = "";

        // case 65: r,s,v signature (standard)
        assembly {
            // Logical shift left of the value
            mstore(add(signature, 0x20), r)
            mstore(add(signature, 0x40), s)
            mstore(add(signature, 0x60), shl(248, v))
            // 65 bytes long
            mstore(signature, 0x41)
            // Update free memory pointer
            mstore(0x40, add(signature, 0x80))
        }

        return signature;
    }

    function signOffer(uint256 signerPrivateKey, Offer memory offer) public returns (bytes memory) {
        // This is the EIP712 signed hash
        bytes32 offerHash = offers.getOfferHash(offer);

        return sign(signerPrivateKey, offerHash);
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
        assertEq(
            lending.getLoanAuction(offer.nftContractAddress, offer.nftId).lastUpdatedTimestamp,
            block.timestamp
        );
    }

    function _test_refinanceLoanByBorrowerSignature_simplest_case(FuzzedOfferFields memory fuzzed)
        private
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        (, LoanAuction memory loanAuction) = createOfferAndTryToExecuteLoanByBorrower(
            offer,
            "should work"
        );

        uint256 initialAmount = offer.amount;

        assertionsForExecutedLoan(offer);

        uint256 interestShortfall = lending.checkSufficientInterestAccumulated(
            offer.nftContractAddress,
            offer.nftId
        );

        Offer memory newOffer = offer;
        newOffer.amount += newOffer.amount;
        bytes memory signature = signOffer(lender1_private_key, offer);

        vm.startPrank(borrower1);
        sigLending.refinanceByBorrowerSignature(
            newOffer,
            signature,
            newOffer.nftId,
            loanAuction.lastUpdatedTimestamp
        );
        vm.stopPrank();

        loanAuction = lending.getLoanAuction(newOffer.nftContractAddress, newOffer.nftId);

        assertEq(
            loanAuction.amountDrawn,
            initialAmount + (offer.interestRatePerSecond * 0) + interestShortfall
        );
        assertEq(loanAuction.amount, newOffer.amount);
    }

    function test_fuzz_refinanceLoanByBorrowerSignature_simplest_case(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        _test_refinanceLoanByBorrowerSignature_simplest_case(fuzzed);
    }

    function test_unit_refinanceLoanByBorrowerSignature_simplest_case() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        _test_refinanceLoanByBorrowerSignature_simplest_case(fixedForSpeed);
    }

    function _test_refinanceLoanByBorrowerSignature_emits_refinance(FuzzedOfferFields memory fuzzed)
        private
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        (, LoanAuction memory loanAuction) = createOfferAndTryToExecuteLoanByBorrower(
            offer,
            "should work"
        );

        uint256 initialAmount = offer.amount;

        assertionsForExecutedLoan(offer);

        uint256 interestShortfall = lending.checkSufficientInterestAccumulated(
            offer.nftContractAddress,
            offer.nftId
        );

        Offer memory newOffer = offer;
        newOffer.amount += newOffer.amount;
        bytes memory signature = signOffer(lender1_private_key, offer);

        vm.expectEmit(true, true, false, true); // Refinance has 2 indexes
        emit Refinance(offer.nftContractAddress, offer.nftId, offer);

        vm.startPrank(borrower1);
        sigLending.refinanceByBorrowerSignature(
            newOffer,
            signature,
            newOffer.nftId,
            loanAuction.lastUpdatedTimestamp
        );
        vm.stopPrank();

        loanAuction = lending.getLoanAuction(newOffer.nftContractAddress, newOffer.nftId);

        assertEq(
            loanAuction.amountDrawn,
            initialAmount + (offer.interestRatePerSecond * 0) + interestShortfall
        );
        assertEq(loanAuction.amount, newOffer.amount);
    }

    function test_fuzz_refinanceLoanByBorrowerSignature_emits_refinance(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        _test_refinanceLoanByBorrowerSignature_emits_refinance(fuzzed);
    }

    function test_unit_refinanceLoanByBorrowerSignature_emits_refinance() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        _test_refinanceLoanByBorrowerSignature_emits_refinance(fixedForSpeed);
    }

    function _test_refinanceLoanByBorrowerSignature_emits_amount_drawn(
        FuzzedOfferFields memory fuzzed
    ) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        (, LoanAuction memory loanAuction) = createOfferAndTryToExecuteLoanByBorrower(
            offer,
            "should work"
        );

        uint256 initialAmount = offer.amount;

        assertionsForExecutedLoan(offer);

        uint256 interestShortfall = lending.checkSufficientInterestAccumulated(
            offer.nftContractAddress,
            offer.nftId
        );

        Offer memory newOffer = offer;
        newOffer.amount += newOffer.amount;
        bytes memory signature = signOffer(lender1_private_key, offer);

        vm.expectEmit(true, true, false, true); // Refinance has 2 indexes
        emit AmountDrawn(
            offer.nftContractAddress,
            offer.nftId,
            (offer.interestRatePerSecond * 0) + interestShortfall,
            initialAmount + (offer.interestRatePerSecond * 0) + interestShortfall
        );

        vm.startPrank(borrower1);
        sigLending.refinanceByBorrowerSignature(
            newOffer,
            signature,
            newOffer.nftId,
            loanAuction.lastUpdatedTimestamp
        );
        vm.stopPrank();

        loanAuction = lending.getLoanAuction(newOffer.nftContractAddress, newOffer.nftId);

        assertEq(
            loanAuction.amountDrawn,
            initialAmount + (offer.interestRatePerSecond * 0) + interestShortfall
        );
        assertEq(loanAuction.amount, newOffer.amount);
    }

    function test_fuzz_refinanceLoanByBorrowerSignature_emits_amount_drawn(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        _test_refinanceLoanByBorrowerSignature_emits_amount_drawn(fuzzed);
    }

    function test_unit_refinanceLoanByBorrowerSignature_emits_amount_drawn() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        _test_refinanceLoanByBorrowerSignature_emits_amount_drawn(fixedForSpeed);
    }

    function _test_refinanceLoanByBorrowerSignature_emits_offer_signature_used(
        FuzzedOfferFields memory fuzzed
    ) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        (, LoanAuction memory loanAuction) = createOfferAndTryToExecuteLoanByBorrower(
            offer,
            "should work"
        );

        uint256 initialAmount = offer.amount;

        assertionsForExecutedLoan(offer);

        uint256 interestShortfall = lending.checkSufficientInterestAccumulated(
            offer.nftContractAddress,
            offer.nftId
        );

        Offer memory newOffer = offer;
        newOffer.amount += newOffer.amount;
        bytes memory signature = signOffer(lender1_private_key, offer);

        vm.expectEmit(true, true, false, true); // OfferSignatureUsed has two indexes
        emit OfferSignatureUsed(offer.nftContractAddress, offer.nftId, newOffer, signature);

        vm.startPrank(borrower1);
        sigLending.refinanceByBorrowerSignature(
            newOffer,
            signature,
            newOffer.nftId,
            loanAuction.lastUpdatedTimestamp
        );
        vm.stopPrank();

        loanAuction = lending.getLoanAuction(newOffer.nftContractAddress, newOffer.nftId);

        assertEq(
            loanAuction.amountDrawn,
            initialAmount + (offer.interestRatePerSecond * 0) + interestShortfall
        );
        assertEq(loanAuction.amount, newOffer.amount);
    }

    function test_fuzz_refinanceLoanByBorrowerSignature_emits_offer_signature_used(
        FuzzedOfferFields memory fuzzed
    ) public validateFuzzedOfferFields(fuzzed) {
        fuzzed.floorTerm = false;
        _test_refinanceLoanByBorrowerSignature_emits_offer_signature_used(fuzzed);
    }

    function test_unit_refinanceLoanByBorrowerSignature_emits_offer_signature_used() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        _test_refinanceLoanByBorrowerSignature_emits_offer_signature_used(fixedForSpeed);
    }
}
