// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract ContractThatCannotReceiveEth is ERC721HolderUpgradeable {
    receive() external payable {
        revert("no Eth!");
    }
}

contract TestExecuteLoanByBorrower is Test, OffersLoansRefinancesFixtures {
    ContractThatCannotReceiveEth private contractThatCannotReceiveEth;

    function setUp() public override {
        super.setUp();

        contractThatCannotReceiveEth = new ContractThatCannotReceiveEth();
    }

    function refinanceSetup(FuzzedOfferFields memory fuzzed, uint16 secondsBeforeRefinance)
        private
    {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        (, LoanAuction memory firstLoan) = createOfferAndTryToExecuteLoanByBorrower(
            offer,
            "should work"
        );

        assertionsForExecutedLoan(offer);

        vm.warp(block.timestamp + secondsBeforeRefinance);

        uint256 hasSufficientInterestAccumulated = lending.checkSufficientInterestAccumulated(
            offer.nftContractAddress,
            offer.nftId
        );

        // new offer from lender2 with +1 amount
        // will trigger term griefing and gas griefing
        defaultFixedOfferFields.creator = lender2;
        fuzzed.duration = fuzzed.duration + 1; // make sure offer is better
        fuzzed.floorTerm = false; // refinance can't be floor term
        fuzzed.expiration = uint32(block.timestamp) + secondsBeforeRefinance + 1;
        console.log("offer.amount", offer.amount);
        console.log(
            "offer.interestRatePerSecond * secondsBeforeRefinance",
            offer.interestRatePerSecond * secondsBeforeRefinance
        );
        console.log("hasSufficientInterestAccumulated", hasSufficientInterestAccumulated);

        fuzzed.amount = uint128(
            offer.amount +
                (offer.interestRatePerSecond * secondsBeforeRefinance) +
                hasSufficientInterestAccumulated
        );

        console.log("fuzzed.amount", fuzzed.amount);
        Offer memory newOffer = offerStructFromFields(fuzzed, defaultFixedOfferFields);

        console.log("hasSufficientInterestAccumulated", hasSufficientInterestAccumulated);

        console.log("newOffer.amount", newOffer.amount);
        // TODO not by borrower, must fix
        tryToRefinanceLoanByBorrower(newOffer, "should work");

        assertionsForExecutedRefinance(
            offer,
            secondsBeforeRefinance,
            hasSufficientInterestAccumulated
        );
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

    function assertionsForExecutedRefinance(
        Offer memory offer,
        uint16 secondsBeforeRefinance,
        uint256 interestShortfall
    ) private {
        // lender1 has money
        if (offer.asset == address(usdcToken)) {
            console.log(assetBalance(lender1, address(usdcToken)));
            console.log(offer.interestRatePerSecond * secondsBeforeRefinance);
            console.log(interestShortfall);
        } else {
            console.log(assetBalance(lender1, ETH_ADDRESS));
            console.log(offer.interestRatePerSecond * secondsBeforeRefinance);
            console.log(interestShortfall);
        }
    }

    function test_unit_refinanceByBorrower(
        FuzzedOfferFields memory fuzzedOffer,
        uint16 secondsBeforeRefinance
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        refinanceSetup(fuzzedOffer, secondsBeforeRefinance);
    }
}
