pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/seaport/ISeaport.sol";

contract TestListNftForSale is Test, OffersLoansRefinancesFixtures, ERC721HolderUpgradeable {
    function setUp() public override {
        // pin block to time of writing test to reflect consistent state
        vm.rollFork(15510097);
        vm.warp(1662833943);

        super.setUp();
    }

    function _test_unit_cancelNftListing_happy_case(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanAuction = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp) / 2);

        uint256 listingValueToBePaidToNiftyApes = _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, loanAuction.loanEndTimestamp);
        // taking the ceil of totalLoanAmount * 40 / 39 (basically adding 2.5% opnesea fee amount)
        uint256 listingPrice = (listingValueToBePaidToNiftyApes * 40 + 38) / 39;

        vm.startPrank(borrower1);
        bytes32 orderHash = sellOnSeaport.listNftForSale(
            offer.nftContractAddress,
            offer.nftId,
            listingPrice,
            block.timestamp,
            loanAuction.loanEndTimestamp,
            1
        );
        vm.stopPrank();

        (bool valid, bool cancelled,,)  = ISeaport(SEAPORT_ADDRESS).getOrderStatus(orderHash);
        assertEq(valid, true);
        assertEq(cancelled, false);

        ISeaport.OrderComponents memory orderComponents = _createOrderComponents(
            offer.nftContractAddress,
            offer.nftId,
            listingPrice,
            loanAuction.loanEndTimestamp,
            loanAuction.asset
        );
        bytes32 orderHashCreated = _getOrderHash(orderComponents);
        assertEq(orderHash, orderHashCreated);
        
        vm.startPrank(borrower1);
        sellOnSeaport.cancelNftListing(orderComponents);
        vm.stopPrank();

        (valid, cancelled,,)  = ISeaport(SEAPORT_ADDRESS).getOrderStatus(orderHash);
        assertEq(valid, false);
        assertEq(cancelled, true);
    }

    function test_unit_cancelNftListing_happy_case_ETH() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cancelNftListing_happy_case(fixedForSpeed);
    }

    function test_unit_cancelNftListing_happy_case_DAI() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0;
        _test_unit_cancelNftListing_happy_case(fixedForSpeed);
    }

    function test_fuzz_cancelNftListing_happy_case(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        _test_unit_cancelNftListing_happy_case(fuzzedOfferData);
    }

    function _test_unit_cannot_cancelNftListing_callerNotBorrower(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanAuction = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp) / 2);

        uint256 listingValueToBePaidToNiftyApes = _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, loanAuction.loanEndTimestamp);
        // taking the ceil of totalLoanAmount * 40 / 39 (basically adding 2.5% opnesea fee amount)
        uint256 listingPrice = (listingValueToBePaidToNiftyApes * 40 + 38) / 39;
        vm.startPrank(borrower1);
        bytes32 orderHash = sellOnSeaport.listNftForSale(
            offer.nftContractAddress,
            offer.nftId,
            listingPrice,
            block.timestamp,
            loanAuction.loanEndTimestamp,
            1
        );
        vm.stopPrank();

        (bool valid, bool cancelled,,)  = ISeaport(SEAPORT_ADDRESS).getOrderStatus(orderHash);
        assertEq(valid, true);
        assertEq(cancelled, false);

        ISeaport.OrderComponents memory orderComponents = _createOrderComponents(
            offer.nftContractAddress,
            offer.nftId,
            listingPrice,
            loanAuction.loanEndTimestamp,
            loanAuction.asset
        );
        bytes32 orderHashCreated = _getOrderHash(orderComponents);
        assertEq(orderHash, orderHashCreated);
        
        vm.startPrank(borrower2);
        vm.expectRevert("00021");
        sellOnSeaport.cancelNftListing(orderComponents);
        vm.stopPrank();

        (valid, cancelled,,)  = ISeaport(SEAPORT_ADDRESS).getOrderStatus(orderHash);
        assertEq(valid, true);
        assertEq(cancelled, false);
    }

    function test_unit_cannot_cancelNftListing_callerNotBorrower() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cannot_cancelNftListing_callerNotBorrower(fixedForSpeed);
    }

    function test_fuzz_cannot_cancelNftListing_callerNotBorrower(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        _test_unit_cannot_cancelNftListing_callerNotBorrower(fuzzedOfferData);
    }

    function _createOrderComponents(
        address nftContractAddress,
        uint256 nftId,
        uint256 listingPrice,
        uint256 listingEndTime,
        address asset
    ) internal view returns (ISeaport.OrderComponents memory) {
        uint256 openseaFeeAmount = listingPrice - (listingPrice * 39) / 40;
        ISeaport.ItemType considerationItemType = (asset == ETH_ADDRESS ? ISeaport.ItemType.NATIVE : ISeaport.ItemType.ERC20);
        address considerationToken = (asset == ETH_ADDRESS ? address(0) : asset);

        ISeaport.OrderComponents memory orderComponents = ISeaport.OrderComponents(
            {
                offerer: address(lending),
                zone: 0x004C00500000aD104D7DBd00e3ae0A5C00560C00,
                offer: new ISeaport.OfferItem[](1),
                consideration: new ISeaport.ConsiderationItem[](2),
                orderType: ISeaport.OrderType.FULL_OPEN,
                startTime: block.timestamp,
                endTime: listingEndTime,
                zoneHash: bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                salt: 1,
                conduitKey: bytes32(0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000),
                counter: ISeaport(SEAPORT_ADDRESS).getCounter(address(lending))
            }
        );

        orderComponents.offer[0] = ISeaport.OfferItem(
            {
                itemType: ISeaport.ItemType.ERC721,
                token: nftContractAddress,
                identifierOrCriteria: nftId,
                startAmount: 1,
                endAmount: 1
            }
        );
        orderComponents.consideration[0] = ISeaport.ConsiderationItem(
            {
                itemType: considerationItemType,
                token: considerationToken,
                identifierOrCriteria: 0,
                startAmount: listingPrice - openseaFeeAmount,
                endAmount:listingPrice - openseaFeeAmount,
                recipient: payable(address(sellOnSeaport))
            }
            
        );
        orderComponents.consideration[1] = ISeaport.ConsiderationItem(
            {
                itemType: considerationItemType,
                token: considerationToken,
                identifierOrCriteria: 0,
                startAmount: openseaFeeAmount,
                endAmount: openseaFeeAmount,
                recipient: payable(0x0000a26b00c1F0DF003000390027140000fAa719)
            }
        );
        return orderComponents;
    }

    function _calculateTotalLoanPaymentAmountAtTimestamp(
        LoanAuction memory loanAuction,
        uint256 timestamp
        ) internal view returns(uint256) {

        uint256 timePassed = timestamp - loanAuction.lastUpdatedTimestamp;

        uint256 lenderInterest = (timePassed * loanAuction.interestRatePerSecond);
        uint256 protocolInterest = (timePassed * loanAuction.protocolInterestRatePerSecond);

        uint256 interestThreshold = (uint256(loanAuction.amountDrawn) * lending.gasGriefingPremiumBps()) /
            10_000;

        lenderInterest = lenderInterest > interestThreshold ? lenderInterest : interestThreshold;

        return loanAuction.accumulatedLenderInterest +
            loanAuction.accumulatedPaidProtocolInterest +
            loanAuction.unpaidProtocolInterest +
            loanAuction.slashableLenderInterest +
            loanAuction.amountDrawn +
            lenderInterest +
            protocolInterest;
    }

    function _getOrderHash(ISeaport.OrderComponents memory orderComponents) internal view returns (bytes32) {
        // Derive order hash by supplying order parameters along with counter.
        return ISeaport(SEAPORT_ADDRESS).getOrderHash(orderComponents);
    }
}
