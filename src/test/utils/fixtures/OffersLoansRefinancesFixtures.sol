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

        uint8 randomAsset = 0; // 0 == USDC, 1 == ETH

        // in addition to fuzz tests, we have fast unit tests
        // using these default values instead of fuzzing
        defaultFixedFuzzedFieldsForFastUnitTesting = FuzzedOfferFields({
            floorTerm: false,
            amount: randomAsset % 2 == 0 ? 10 * uint128(10**usdcToken.decimals()) : 1 ether,
            interestRatePerSecond: randomAsset % 2 == 0 ? 100 : 10**6,
            duration: 1 weeks,
            expiration: uint32(block.timestamp) + 1 days,
            randomAsset: randomAsset
        });
    }

    modifier validateFuzzedOfferFields(FuzzedOfferFields memory fuzzed) {
        // -10 ether to give refinancing lender some wiggle room for fees
        if (fuzzed.randomAsset % 2 == 0) {
            vm.assume(fuzzed.amount > 0);
            vm.assume(fuzzed.amount < (defaultUsdcLiquiditySupplied * 90) / 100);
        } else {
            vm.assume(fuzzed.amount > 0);
            vm.assume(fuzzed.amount < (defaultEthLiquiditySupplied * 90) / 100);
        }

        vm.assume(fuzzed.duration > 1 days);
        // to avoid overflow when loanAuction.loanEndTimestamp = _currentTimestamp32() + offer.duration;
        vm.assume(fuzzed.duration < ~uint32(0) - block.timestamp);
        vm.assume(fuzzed.expiration > block.timestamp);
        // to avoid "Division or modulo by 0"
        vm.assume(fuzzed.interestRatePerSecond > 0);
        // don't want interest to be too much for refinancing lender
        vm.assume(fuzzed.interestRatePerSecond < (fuzzed.randomAsset % 2 == 0 ? 100 : 10**13));
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
                amount: fuzzed.amount + (fuzzed.randomAsset % 2) == 0
                    ? 10 * uint128(10**usdcToken.decimals())
                    : 250000000,
                duration: fuzzed.duration,
                expiration: fuzzed.expiration
            });
    }

    function createOffer(Offer memory offer, address lender) internal returns (Offer memory) {
        vm.startPrank(lender);
        offer.creator = lender;
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
        Offer memory offerCreated = createOffer(offer, lender1);
        approveLending(offer);
        LoanAuction memory loan = tryToExecuteLoanByBorrower(offer, errorCode);
        return (offerCreated, loan);
    }

    function tryToRefinanceByLender(Offer memory newOffer, bytes memory errorCode)
        internal
        returns (LoanAuction memory)
    {
        vm.startPrank(lender2);
        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }
        lending.refinanceByLender(
            newOffer,
            lending.getLoanAuction(address(mockNft), 1).lastUpdatedTimestamp
        );
        vm.stopPrank();
        return lending.getLoanAuction(newOffer.nftContractAddress, newOffer.nftId);
    }

    function createOfferAndTryToRefinanceByLender(Offer memory newOffer, bytes memory errorCode)
        internal
        returns (Offer memory, LoanAuction memory)
    {
        Offer memory offerCreated = createOffer(newOffer, lender2);
        LoanAuction memory loan = tryToRefinanceByLender(offerCreated, errorCode);
        return (offerCreated, loan);
    }

    function assetBalance(address account, address asset) internal returns (uint256) {
        address cAsset = liquidity.assetToCAsset(asset);

        uint256 cTokens = liquidity.getCAssetBalance(account, address(cAsset));

        return liquidity.cAssetAmountToAssetAmount(address(cAsset), cTokens);
    }

    function assetBalancePlusOneCToken(address account, address asset) internal returns (uint256) {
        address cAsset = liquidity.assetToCAsset(asset);

        uint256 cTokens = liquidity.getCAssetBalance(account, address(cAsset)) + 1;

        return liquidity.cAssetAmountToAssetAmount(address(cAsset), cTokens);
    }
}
