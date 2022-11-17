// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../mock/FlashSellReceiverMock.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";

contract TestFlashSell is Test, ILendingStructs, OffersLoansRefinancesFixtures {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    function setUp() public override {
        super.setUp();
    }

    function _test_unit_flashSell_simplest_case(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanBefore = lending.getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );
        // skip time to accrue interest
        skip(uint256(loanBefore.loanEndTimestamp - loanBefore.loanBeginTimestamp) / 2);

        FlashSellReceiverMock flashSellReceiverHappyMock = _createFlashSellReceiverMock(
            true,
            offer.nftContractAddress,
            offer.nftId,
            loanBefore
        );

        address nftOwnerBefore = IERC721Upgradeable(offer.nftContractAddress).ownerOf(offer.nftId);
        uint256 flashSellAssetBalanceBefore;
        if (loanBefore.asset == ETH_ADDRESS) {
            flashSellAssetBalanceBefore = address(flashSell).balance;
        } else {
            flashSellAssetBalanceBefore = IERC20Upgradeable(loanBefore.asset).balanceOf(
                address(flashSell)
            );
        }

        vm.startPrank(borrower1);
        flashSell.borrowNFTForSale(
            offer.nftContractAddress,
            offer.nftId,
            address(flashSellReceiverHappyMock),
            bytes("")
        );
        vm.stopPrank();

        LoanAuction memory loanAfter = lending.getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );
        address nftOwnerAfter = IERC721Upgradeable(offer.nftContractAddress).ownerOf(offer.nftId);
        uint256 flashSellAssetBalanceAfter;
        if (loanBefore.asset == ETH_ADDRESS) {
            flashSellAssetBalanceAfter = address(flashSell).balance;
        } else {
            flashSellAssetBalanceAfter = IERC20Upgradeable(loanBefore.asset).balanceOf(
                address(flashSell)
            );
        }
        assertEq(address(lending), nftOwnerBefore);
        assertEq(address(flashSellReceiverHappyMock), nftOwnerAfter);
        assertEq(flashSellAssetBalanceBefore, flashSellAssetBalanceAfter);
        assertEq(loanAfter.loanBeginTimestamp, 0);
    }

    function test_unit_flashSell_simplest_case_ETH() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_flashSell_simplest_case(fixedForSpeed);
    }

    function test_fuzz_flashSell_simplest_case_ETH(FuzzedOfferFields memory fuzzedOfferData)
        public
        validateFuzzedOfferFields(fuzzedOfferData)
    {
        fuzzedOfferData.randomAsset = 1;
        _test_unit_flashSell_simplest_case(fuzzedOfferData);
    }

    function test_unit_flashSell_simplest_case_DAI() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0;
        _test_unit_flashSell_simplest_case(fixedForSpeed);
    }

    function test_fuzz_flashSell_simplest_case_DAI(FuzzedOfferFields memory fuzzedOfferData)
        public
        validateFuzzedOfferFields(fuzzedOfferData)
    {
        fuzzedOfferData.randomAsset = 0;
        _test_unit_flashSell_simplest_case(fuzzedOfferData);
    }

    function _test_unit_cannot_flashSell_notNftOwner(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanBefore = lending.getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );

        FlashSellReceiverMock flashSellReceiverHappyMock = _createFlashSellReceiverMock(
            true,
            offer.nftContractAddress,
            offer.nftId,
            loanBefore
        );

        vm.startPrank(borrower2);
        vm.expectRevert("00021");
        flashSell.borrowNFTForSale(
            offer.nftContractAddress,
            offer.nftId,
            address(flashSellReceiverHappyMock),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_unit_cannot_flashSell_notNftOwner() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cannot_flashSell_notNftOwner(fixedForSpeed);
    }

    function _test_unit_cannot_flashSell_noReturn(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanBefore = lending.getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );

        FlashSellReceiverMock flashSellReceiverNotHappyMock = _createFlashSellReceiverMock(
            false,
            offer.nftContractAddress,
            offer.nftId,
            loanBefore
        );

        vm.startPrank(borrower1);
        vm.expectRevert("00057");
        flashSell.borrowNFTForSale(
            offer.nftContractAddress,
            offer.nftId,
            address(flashSellReceiverNotHappyMock),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_unit_cannot_flashSell_noReturn() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cannot_flashSell_noReturn(fixedForSpeed);
    }

    function _createFlashSellReceiverMock(
        bool happyState,
        address nftContractAddress,
        uint256 nftId,
        LoanAuction memory loan
    ) private returns (FlashSellReceiverMock) {
        FlashSellReceiverMock flashSellReceiverMock = new FlashSellReceiverMock();
        flashSellReceiverMock.updateHappyState(happyState);

        if (loan.asset == ETH_ADDRESS) {
            vm.startPrank(borrower1);
            payable(address(flashSellReceiverMock)).sendValue(
                _calculateTotalLoanPaymentAmount(nftContractAddress, nftId, loan)
            );
            vm.stopPrank();
        } else {
            mintDai(
                address(flashSellReceiverMock),
                _calculateTotalLoanPaymentAmount(nftContractAddress, nftId, loan)
            );
        }

        return flashSellReceiverMock;
    }

    function _calculateTotalLoanPaymentAmount(
        address nftContractAddress,
        uint256 nftId,
        LoanAuction memory loanAuction
    ) private view returns (uint256) {
        uint256 interestThresholdDelta;

        if (loanAuction.loanEndTimestamp - 1 days > uint32(block.timestamp)) {
            interestThresholdDelta = lending.checkSufficientInterestAccumulated(
                nftContractAddress,
                nftId
            );
        }

        (uint256 lenderInterest, uint256 protocolInterest) = lending.calculateInterestAccrued(
            nftContractAddress,
            nftId
        );

        return
            uint256(loanAuction.accumulatedLenderInterest) +
            loanAuction.accumulatedPaidProtocolInterest +
            loanAuction.unpaidProtocolInterest +
            loanAuction.slashableLenderInterest +
            loanAuction.amountDrawn +
            interestThresholdDelta +
            lenderInterest +
            protocolInterest;
    }
}
