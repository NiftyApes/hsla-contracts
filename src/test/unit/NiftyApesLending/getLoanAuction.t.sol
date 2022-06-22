// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/LenderLiquidityFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract ContractThatCannotReceiveEth is ERC721HolderUpgradeable {
    receive() external payable {
        revert("no Eth!");
    }
}

contract TestExecuteLoanByBorrower is
    Test,
    IOffersStructs,
    ILendingStructs,
    ILendingEvents,
    LenderLiquidityFixtures
{
    struct FuzzedOfferFields {
        bool fixedTerms;
        bool floorTerm;
        uint128 amount;
        uint96 interestRatePerSecond;
        uint32 duration;
        uint32 expiration;
        uint8 randomAsset; // asset = randomAsset % 2 == 0 ? USDC : ETH
    }

    struct FixedOfferFields {
        address creator;
        bool lenderOffer;
        uint256 nftId;
        address nftContractAddress;
    }

    FixedOfferFields private defaultFixedOfferFields;

    FuzzedOfferFields private defaultFixedFuzzedFieldsForFastUnitTesting;

    ContractThatCannotReceiveEth private contractThatCannotReceiveEth;

    function setUp() public override {
        super.setUp();

        // these fields are fixed, not fuzzed
        // but specific fields can be overridden in tests
        defaultFixedOfferFields = FixedOfferFields({
            creator: lender1,
            lenderOffer: true,
            nftContractAddress: address(mockNft),
            nftId: 1
        });

        // in addition to fuzz tests, we have fast unit tests
        // using these default values instead of fuzzing
        defaultFixedFuzzedFieldsForFastUnitTesting = FuzzedOfferFields({
            fixedTerms: false,
            floorTerm: false,
            amount: 1 ether,
            interestRatePerSecond: 10**13,
            duration: 1 weeks,
            expiration: uint32(block.timestamp) + 1 days,
            randomAsset: 0
        });

        contractThatCannotReceiveEth = new ContractThatCannotReceiveEth();
    }

    modifier validateFuzzedOfferFields(FuzzedOfferFields memory fuzzed) {
        vm.assume(fuzzed.amount > 0);
        vm.assume(fuzzed.amount < defaultLiquiditySupplied);
        vm.assume(fuzzed.duration > 1 days);
        // to avoid overflow when loanAuction.loanEndTimestamp = _currentTimestamp32() + offer.duration;
        vm.assume(fuzzed.duration < ~uint32(0) - block.timestamp);
        vm.assume(fuzzed.expiration > block.timestamp);
        _;
    }

    function offerStructFromFields(
        FuzzedOfferFields memory fuzzed,
        FixedOfferFields memory fixedFields
    ) private view returns (Offer memory) {
        address asset = fuzzed.randomAsset % 2 == 0 ? address(usdcToken) : address(ETH_ADDRESS);

        return
            Offer({
                creator: fixedFields.creator,
                lenderOffer: fixedFields.lenderOffer,
                nftId: fixedFields.nftId,
                nftContractAddress: fixedFields.nftContractAddress,
                asset: asset,
                fixedTerms: fuzzed.fixedTerms,
                floorTerm: fuzzed.floorTerm,
                interestRatePerSecond: fuzzed.interestRatePerSecond,
                amount: fuzzed.amount,
                duration: fuzzed.duration,
                expiration: fuzzed.expiration
            });
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

    function createOffer(Offer memory offer) private returns (Offer memory) {
        vm.startPrank(lender1);
        bytes32 offerHash = offers.createOffer(offer);
        vm.stopPrank();
        return offers.getOffer(offer.nftContractAddress, offer.nftId, offerHash, offer.floorTerm);
    }

    function approveLending(Offer memory offer) private {
        vm.startPrank(borrower1);
        mockNft.approve(address(lending), offer.nftId);
        vm.stopPrank();
    }

    function tryToExecuteLoanByBorrower(Offer memory offer, bytes memory errorCode)
        private
        returns (LoanAuction memory)
    {
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

        return lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
    }

    function createOfferAndTryToExecuteLoanByBorrower(Offer memory offer, bytes memory errorCode)
        private
        returns (Offer memory, LoanAuction memory)
    {
        Offer memory offerCreated = createOffer(offer);
        approveLending(offer);
        LoanAuction memory loan = tryToExecuteLoanByBorrower(offer, errorCode);
        return (offerCreated, loan);
    }

    function _test_getLoanAuction_works(FuzzedOfferFields memory fuzzed) private {
        Offer memory offerToCreate = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        (Offer memory offer, LoanAuction memory loan) = createOfferAndTryToExecuteLoanByBorrower(
            offerToCreate,
            "should work"
        );

        assertEq(loan.nftOwner, borrower1);
        assertEq(loan.lender, offer.creator);
        assertEq(loan.asset, offer.asset);
        assertEq(loan.amount, offer.amount);
        assertEq(loan.loanEndTimestamp, offer.duration + block.timestamp);
        assertEq(loan.loanBeginTimestamp, block.timestamp);
        assertEq(loan.lastUpdatedTimestamp, block.timestamp);
        assertEq(loan.amountDrawn, offer.amount);
        assertEq(loan.fixedTerms, offer.fixedTerms);
        assertEq(loan.lenderRefi, false);
        assertEq(loan.accumulatedLenderInterest, 0);
        assertEq(loan.accumulatedProtocolInterest, 0);
        assertEq(loan.interestRatePerSecond, offer.interestRatePerSecond);
    }

    function test_fuzz_getLoanAuction_works(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        _test_getLoanAuction_works(fuzzed);
    }
}
