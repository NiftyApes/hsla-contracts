pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";

contract TestDrawLoanAmount is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function _test_executeLoanByBorrower_simplest_case(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");
        assertionsForExecutedLoan(offer);
    }

    function test_fuzz_executeLoanByBorrower_simplest_case(FuzzedOfferFields memory fuzzed)
        public
        validateFuzzedOfferFields(fuzzed)
    {
        _test_executeLoanByBorrower_simplest_case(fuzzed);
    }
}
