// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/LenderLiquidityFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

uint256 constant MAX_BPS = 10_000;
uint256 constant MAX_FEE = 1_000;

contract OffersLoansRefinancesFixtures is
    Test,
    IOffersStructs,
    ILendingEvents,
    ILendingStructs,
    LenderLiquidityFixtures
{
    struct FuzzedOfferFields {
        bool floorTerm;
        uint128 amount;
        uint96 interestRatePerSecond;
        uint32 duration;
        uint32 expiration;
        uint8 randomAsset; // asset = randomAsset % 2 == 0 ? USDC : ETH
    }

    struct FixedOfferFields {
        bool fixedTerms;
        address creator;
        bool lenderOffer;
        uint256 nftId;
        address nftContractAddress;
    }

    FixedOfferFields internal defaultFixedOfferFields;

    FuzzedOfferFields internal defaultFixedFuzzedFieldsForFastUnitTesting;

    function setUp() public virtual override {
        super.setUp();

        // these fields are fixed, not fuzzed
        // but specific fields can be overridden in tests
        defaultFixedOfferFields = FixedOfferFields({
            fixedTerms: false,
            creator: lender1,
            lenderOffer: true,
            nftContractAddress: address(mockNft),
            nftId: 1
        });

        // in addition to fuzz tests, we have fast unit tests
        // using these default values instead of fuzzing
        defaultFixedFuzzedFieldsForFastUnitTesting = FuzzedOfferFields({
            floorTerm: false,
            amount: 1 ether,
            interestRatePerSecond: 10**13,
            duration: 1 weeks,
            expiration: uint32(block.timestamp) + 1 days,
            randomAsset: 0
        });
    }

    modifier validateFuzzedOfferFields(FuzzedOfferFields memory fuzzed) {
        vm.assume(fuzzed.amount > 0);
        // -10 ether to give refinancing lender some wiggle room for fees
        vm.assume(fuzzed.amount < defaultLiquiditySupplied - 10 ether);
        vm.assume(fuzzed.duration > 1 days);
        // to avoid overflow when loanAuction.loanEndTimestamp = _currentTimestamp32() + offer.duration;
        vm.assume(fuzzed.duration < ~uint32(0) - block.timestamp);
        vm.assume(fuzzed.expiration > block.timestamp);
        // to avoid "Division or modulo by 0"
        vm.assume(fuzzed.interestRatePerSecond > 0);
        vm.assume(fuzzed.interestRatePerSecond < 10**13);
        _;
    }

    function offerStructFromFields(
        FuzzedOfferFields memory fuzzed,
        FixedOfferFields memory fixedFields
    ) internal view returns (Offer memory) {
        address asset = fuzzed.randomAsset % 2 == 0 ? address(usdcToken) : address(ETH_ADDRESS);

        return
            Offer({
                creator: fixedFields.creator,
                lenderOffer: fixedFields.lenderOffer,
                nftId: fixedFields.nftId,
                nftContractAddress: fixedFields.nftContractAddress,
                fixedTerms: fixedFields.fixedTerms,
                asset: asset,
                floorTerm: fuzzed.floorTerm,
                interestRatePerSecond: fuzzed.interestRatePerSecond,
                amount: fuzzed.amount,
                duration: fuzzed.duration,
                expiration: fuzzed.expiration
            });
    }

    function createOffer(Offer memory offer) internal returns (Offer memory) {
        vm.startPrank(lender1);
        bytes32 offerHash = offers.createOffer(offer);
        vm.stopPrank();
        return offers.getOffer(offer.nftContractAddress, offer.nftId, offerHash, offer.floorTerm);
    }

    function approveLending(Offer memory offer) internal {
        vm.startPrank(borrower1);
        mockNft.approve(address(lending), offer.nftId);
        vm.stopPrank();
    }

    function tryToExecuteLoanByBorrower(Offer memory offer, bytes memory errorCode)
        internal
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
        internal
        returns (Offer memory, LoanAuction memory)
    {
        Offer memory offerCreated = createOffer(offer);
        approveLending(offer);
        LoanAuction memory loan = tryToExecuteLoanByBorrower(offer, errorCode);
        return (offerCreated, loan);
    }

    function tryToRefinanceLoan(Offer memory newOffer, bytes memory errorCode) internal {
        vm.startPrank(lender2);
        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }
        lending.refinanceByLender(
            newOffer,
            lending.getLoanAuction(address(mockNft), 1).lastUpdatedTimestamp
        );
        vm.stopPrank();
    }

    function assetBalance(address account, address asset) internal returns (uint256) {
        address cAsset = liquidity.assetToCAsset(asset);
        return
            liquidity.cAssetAmountToAssetAmount(
                address(cAsset),
                liquidity.getCAssetBalance(account, address(cAsset))
            );
    }
}
