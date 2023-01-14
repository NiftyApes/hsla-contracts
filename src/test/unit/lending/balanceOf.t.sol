// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestBalanceOf is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_balanceOf_withANewLoan(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        uint256 balanceBefore = lending.balanceOf(borrower1, address(mockNft));

        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        uint256 balanceAfter = lending.balanceOf(borrower1, address(mockNft));
        assertEq(balanceAfter, balanceBefore + 1);
    }

    function test_fuzz_balanceOf_withANewLoan(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        _test_balanceOf_withANewLoan(fuzzed);
    }

    function test_unit_balanceOf_withANewLoan() public {
        _test_balanceOf_withANewLoan(defaultFixedFuzzedFieldsForFastUnitTesting);
    }

    function _test_balanceOf_withANewLoan_ERC1155(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        offer.nftContractAddress = address(mockERC1155Token);
        offer.nftId = 1;
        uint256 balanceBefore = lending.balanceOf(borrower1, address(mockERC1155Token));

        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        uint256 balanceAfter = lending.balanceOf(borrower1, address(mockERC1155Token));
        assertEq(balanceAfter, balanceBefore + 1);
    }

    function test_fuzz_balanceOf_withANewLoan_ERC1155(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        _test_balanceOf_withANewLoan_ERC1155(fuzzed);
    }

    function test_unit_balanceOf_withANewLoan_ERC1155() public {
        _test_balanceOf_withANewLoan_ERC1155(defaultFixedFuzzedFieldsForFastUnitTesting);
    }

    function _test_balanceOf_afterClosingAnActiveLoan(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        uint256 balanceBefore = lending.balanceOf(borrower1, address(mockNft));

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

        uint256 balanceAfter = lending.balanceOf(borrower1, address(mockNft));
        assertEq(balanceAfter, balanceBefore - 1);
    }

    function test_fuzz_balanceOf_afterClosingAnActiveLoan(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        fuzzed.randomAsset = 0; // DAI
        _test_balanceOf_afterClosingAnActiveLoan(fuzzed);
    }

    function test_unit_balanceOf_afterClosingAnActiveLoan() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0; // DAI
        _test_balanceOf_afterClosingAnActiveLoan(fixedForSpeed);
    }

    function _test_balanceOf_afterSeizingAsset(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        uint256 balanceBefore = lending.balanceOf(borrower1, address(mockNft));

        // warp to end of loan
        vm.warp(block.timestamp + offer.duration);
        // seize asset
        vm.startPrank(lender1);
        lending.seizeAsset(offer.nftContractAddress, offer.nftId);
        vm.stopPrank();

        uint256 balanceAfter = lending.balanceOf(borrower1, address(mockNft));
        assertEq(balanceAfter, balanceBefore - 1);
    }

    function test_fuzz_balanceOf_afterSeizingAsset(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        fuzzed.randomAsset = 0; // DAI
        _test_balanceOf_afterClosingAnActiveLoan(fuzzed);
    }

    function test_unit_balanceOf_afterSeizingAsset() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0; // DAI
        _test_balanceOf_afterClosingAnActiveLoan(fixedForSpeed);
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
