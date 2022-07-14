// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestUpdateDefaultRefinancePremiumBps is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_updateDefaultRefinancePremiumBps_works(
        FuzzedOfferFields memory fuzzed,
        uint16 updatedDefaultRefinancePremiumAmount
    ) private {
        vm.startPrank(owner);
        lending.updateDefaultRefinancePremiumBps(updatedDefaultRefinancePremiumAmount);
        vm.stopPrank();

        assertEq(lending.defaultRefinancePremiumBps(), updatedDefaultRefinancePremiumAmount);

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
        fuzzed.expiration = firstLoan.loanEndTimestamp - 1;
        Offer memory newOffer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        vm.warp(firstLoan.loanEndTimestamp - 2);

        tryToRefinanceByLender(newOffer, "should work");

        uint256 interest = offer.interestRatePerSecond *
            (block.timestamp - firstLoan.lastUpdatedTimestamp);

        uint256 threshold = (lending.gasGriefingPremiumBps() * firstLoan.amountDrawn) / MAX_BPS;

        // uint256 griefingToLender = threshold - interest;

        uint256 gasGriefingToProtocol = (interest * lending.gasGriefingProtocolPremiumBps()) /
            MAX_BPS;

        uint256 termGriefingToProtocol = (lending.termGriefingPremiumBps() *
            firstLoan.amountDrawn) / MAX_BPS;

        uint256 defaultPremiumToProtocol = (lending.defaultRefinancePremiumBps() *
            firstLoan.amountDrawn) / MAX_BPS;

        console.log("interest", interest);
        console.log("threshold", threshold);
        console.log(
            "defaultPremiumToProtocol",
            defaultPremiumToProtocol + gasGriefingToProtocol + termGriefingToProtocol
        );
        console.log("lower", assetBalance(owner, address(usdcToken)));
        console.log("upper", assetBalancePlusOneCToken(owner, address(usdcToken)));

        if (offer.asset == address(usdcToken)) {
            if (interest < threshold) {
                assertBetween(
                    defaultPremiumToProtocol + gasGriefingToProtocol + termGriefingToProtocol,
                    assetBalance(owner, address(usdcToken)),
                    assetBalancePlusOneCToken(owner, address(usdcToken))
                );
            } else {
                assertBetween(
                    defaultPremiumToProtocol + termGriefingToProtocol,
                    assetBalance(owner, address(usdcToken)),
                    assetBalancePlusOneCToken(owner, address(usdcToken))
                );
            }
        } else {
            if (interest < threshold) {
                assertBetween(
                    defaultPremiumToProtocol + gasGriefingToProtocol + termGriefingToProtocol,
                    assetBalance(owner, ETH_ADDRESS),
                    assetBalancePlusOneCToken(owner, ETH_ADDRESS)
                );
            } else {
                assertBetween(
                    defaultPremiumToProtocol + termGriefingToProtocol,
                    assetBalance(owner, ETH_ADDRESS),
                    assetBalancePlusOneCToken(owner, ETH_ADDRESS)
                );
            }
        }
    }

    function test_fuzz_updateDefaultRefinancePremiumBps_works(
        FuzzedOfferFields memory fuzzedOffer,
        uint16 updatedDefaultRefinancePremiumAmount
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        vm.assume(updatedDefaultRefinancePremiumAmount < MAX_FEE);

        _test_updateDefaultRefinancePremiumBps_works(
            fuzzedOffer,
            updatedDefaultRefinancePremiumAmount
        );
    }

    function test_unit_updateDefaultRefinancePremiumBps_works() public {
        uint16 updatedDefaultRefinancePremiumAmount = 500;

        _test_updateDefaultRefinancePremiumBps_works(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            updatedDefaultRefinancePremiumAmount
        );
    }

    function _test_cannot_updateDefaultRefinancePremiumBps_if_not_owner() private {
        uint16 updatedDefaultRefinancePremiumAmount = 500;

        vm.startPrank(borrower1);
        vm.expectRevert("Ownable: caller is not the owner");
        lending.updateDefaultRefinancePremiumBps(updatedDefaultRefinancePremiumAmount);
        vm.stopPrank();
    }

    function test_unit_cannot_updateDefaultRefinancePremiumBps_if_not_owner() public {
        _test_cannot_updateDefaultRefinancePremiumBps_if_not_owner();
    }

    function _test_cannot_updateDefaultRefinancePremiumBps_beyond_max_bps() private {
        uint16 updatedDefaultRefinancePremiumAmount = 1_001;

        vm.startPrank(owner);
        vm.expectRevert("00002");
        lending.updateDefaultRefinancePremiumBps(updatedDefaultRefinancePremiumAmount);
        vm.stopPrank();
    }

    function test_unit_cannot_updateDefaultRefinancePremiumBps_beyond_max_bps() public {
        _test_cannot_updateDefaultRefinancePremiumBps_beyond_max_bps();
    }
}
