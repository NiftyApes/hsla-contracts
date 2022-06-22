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

contract TestExecuteLoanByBorrower is
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

    FixedOfferFields private defaultFixedOfferFields;

    FuzzedOfferFields private defaultFixedFuzzedFieldsForFastUnitTesting;

    function setUp() public override {
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
    ) private view returns (Offer memory) {
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

    function tryToRefinanceLoan(Offer memory newOffer, bytes memory errorCode) private {
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

    function assetBalance(address account, address asset) private returns (uint256) {
        address cAsset = liquidity.assetToCAsset(asset);
        return
            liquidity.cAssetAmountToAssetAmount(
                address(cAsset),
                liquidity.getCAssetBalance(account, address(cAsset))
            );
    }

    function _test_updateGasGriefingProtocolPremiumBps_works(
        FuzzedOfferFields memory fuzzed,
        uint16 secondsBeforeRefinance,
        uint16 updatedGasGriefingAmount
    ) private {
        vm.startPrank(owner);
        lending.updateGasGriefingProtocolPremiumBps(updatedGasGriefingAmount);
        vm.stopPrank();

        assertEq(lending.gasGriefingProtocolPremiumBps(), updatedGasGriefingAmount);

        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        (, LoanAuction memory firstLoan) = createOfferAndTryToExecuteLoanByBorrower(
            offer,
            "should work"
        );

        // new offer from lender2 with +1 amount
        // will trigger term griefing and gas griefing
        defaultFixedOfferFields.creator = lender2;
        fuzzed.duration = fuzzed.duration + 1; // make sure offer is better
        fuzzed.floorTerm = false; // refinance can't be floor term
        fuzzed.expiration = uint32(block.timestamp) + secondsBeforeRefinance + 1;
        Offer memory newOffer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        vm.warp(block.timestamp + secondsBeforeRefinance);

        tryToRefinanceLoan(newOffer, "should work");

        uint256 interest = offer.interestRatePerSecond * secondsBeforeRefinance;

        uint256 threshold = (lending.gasGriefingPremiumBps() * firstLoan.amountDrawn) / MAX_BPS;

        // uint256 griefingToLender = threshold - interest;

        uint256 gasGriefingToProtocol = (interest * lending.gasGriefingProtocolPremiumBps()) /
            MAX_BPS;

        uint256 termGriefingToProtocol = (lending.termGriefingPremiumBps() *
            firstLoan.amountDrawn) / MAX_BPS;

        if (offer.asset == address(usdcToken)) {
            if (interest < threshold) {
                assertEq(
                    assetBalance(owner, address(usdcToken)),
                    gasGriefingToProtocol + termGriefingToProtocol
                );
            } else {
                assertEq(assetBalance(owner, address(usdcToken)), termGriefingToProtocol);
            }
        } else {
            if (interest < threshold) {
                assertEq(
                    assetBalance(owner, ETH_ADDRESS),
                    gasGriefingToProtocol + termGriefingToProtocol
                );
            } else {
                assertEq(assetBalance(owner, ETH_ADDRESS), termGriefingToProtocol);
            }
        }
    }

    function test_fuzz_updateGasGriefingProtocolPremiumBps_works(
        FuzzedOfferFields memory fuzzedOffer,
        uint16 secondsBeforeRefinance,
        uint16 updatedGasGriefingAmount
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        vm.assume(updatedGasGriefingAmount < MAX_BPS);
        _test_updateGasGriefingProtocolPremiumBps_works(
            fuzzedOffer,
            secondsBeforeRefinance,
            updatedGasGriefingAmount
        );
    }

    function test_unit_updateGasGriefingProtocolPremiumBps_works() public {
        uint16 secondsBeforeRefinance = 300;
        uint16 updatedGasGriefingAmount = 5000;
        _test_updateGasGriefingProtocolPremiumBps_works(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            secondsBeforeRefinance,
            updatedGasGriefingAmount
        );
    }

    function _test_cannot_updateGasGriefingProtocolPremiumBps_if_not_owner() private {
        uint16 updatedGasGriefingAmount = 5000;

        vm.startPrank(borrower1);
        vm.expectRevert("Ownable: caller is not the owner");
        lending.updateGasGriefingProtocolPremiumBps(updatedGasGriefingAmount);
        vm.stopPrank();
    }

    function test_unit_cannot_updateGasGriefingProtocolPremiumBps_if_not_owner() public {
        _test_cannot_updateGasGriefingProtocolPremiumBps_if_not_owner();
    }

    function _test_cannot_updateGasGriefingProtocolPremiumBps_beyond_max_bps() private {
        uint16 updatedGasGriefingAmount = 10_001;

        vm.startPrank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        lending.updateGasGriefingProtocolPremiumBps(updatedGasGriefingAmount);
        vm.stopPrank();
    }

    function test_unit_cannot_updateGasGriefingProtocolPremiumBps_beyond_max_bps() public {
        _test_cannot_updateGasGriefingProtocolPremiumBps_if_not_owner();
    }
}
