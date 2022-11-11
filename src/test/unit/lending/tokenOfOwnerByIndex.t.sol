// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestTokenOfOwnerByIndex is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_tokenOfOwnerByIndex_withANewLoan(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        assertEq(lending.tokenOfOwnerByIndex(borrower1, address(mockNft), 0), 1);
    }

    function test_fuzz_tokenOfOwnerByIndex_withANewLoan(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        _test_tokenOfOwnerByIndex_withANewLoan(fuzzed);
    }

    function test_unit_tokenOfOwnerByIndex_withANewLoan() public {
        _test_tokenOfOwnerByIndex_withANewLoan(defaultFixedFuzzedFieldsForFastUnitTesting);
    }

    function _test_cannot_tokenOfOwnerByIndex_afterClosingAnActiveLoan(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        assertEq(lending.tokenOfOwnerByIndex(borrower1, address(mockNft), 0), 1);

        _calculateTotalLoanPaymentAmount(offer.nftContractAddress, offer.nftId);
        // Give borrower enough to pay interest
        mintDai(borrower1, _calculateTotalLoanPaymentAmount(offer.nftContractAddress, offer.nftId));

        vm.startPrank(borrower1);
        daiToken.approve(address(liquidity), ~uint256(0));
        lending.repayLoan(
            offer.nftContractAddress,
            offer.nftId
        );
        vm.stopPrank();

        vm.expectRevert("00069");
        lending.tokenOfOwnerByIndex(borrower1, address(mockNft), 0);
    }

    function test_fuzz_cannot_tokenOfOwnerByIndex_afterClosingAnActiveLoan(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        fuzzed.randomAsset = 0; // DAI
        _test_cannot_tokenOfOwnerByIndex_afterClosingAnActiveLoan(fuzzed);
    }

    function test_unit_cannot_tokenOfOwnerByIndex_afterClosingAnActiveLoan() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0; // DAI
        _test_cannot_tokenOfOwnerByIndex_afterClosingAnActiveLoan(fixedForSpeed);
    }

    function _test_cannot_tokenOfOwnerByIndex_afterSeizingAsset(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        assertEq(lending.tokenOfOwnerByIndex(borrower1, address(mockNft), 0), 1);

        // warp to end of loan
        vm.warp(block.timestamp + offer.duration);
        // seize asset
        vm.startPrank(lender1);
        lending.seizeAsset(offer.nftContractAddress, offer.nftId);
        vm.stopPrank();

        vm.expectRevert("00069");
        lending.tokenOfOwnerByIndex(borrower1, address(mockNft), 0);
    }

    function test_fuzz_cannot_tokenOfOwnerByIndex_afterSeizingAsset(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        fuzzed.randomAsset = 0; // DAI
        _test_cannot_tokenOfOwnerByIndex_afterClosingAnActiveLoan(fuzzed);
    }

    function test_unit_cannot_tokenOfOwnerByIndex_afterSeizingAsset() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0; // DAI
        _test_cannot_tokenOfOwnerByIndex_afterClosingAnActiveLoan(fixedForSpeed);
    }

    function _calculateTotalLoanPaymentAmount(
        address nftContractAddress,
        uint256 nftId
        ) internal view returns(uint256) {
        LoanAuction memory loanAuction = ILending(lending).getLoanAuction(nftContractAddress, nftId);
        uint256 interestThresholdDelta = 
            ILending(lending).checkSufficientInterestAccumulated(
                nftContractAddress,
                nftId
            );

        (uint256 lenderInterest, uint256 protocolInterest) = 
            ILending(lending).calculateInterestAccrued(
                nftContractAddress,
                nftId
            );

        return uint256(loanAuction.accumulatedLenderInterest) +
                loanAuction.accumulatedPaidProtocolInterest +
                loanAuction.unpaidProtocolInterest +
                loanAuction.slashableLenderInterest +
                loanAuction.amountDrawn +
                interestThresholdDelta +
                lenderInterest +
                protocolInterest;
    }
}
