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

    function _test_unit_validateSaleAndWithdraw_happy_case(FuzzedOfferFields memory fuzzed, bool lenderCall) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanAuction = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp) / 2);

        
        uint256 listingValueToBePaidToNiftyApes = _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, loanAuction.loanEndTimestamp);
        uint256 profitForTheBorrower = listingValueToBePaidToNiftyApes - _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, block.timestamp); // assume any profit the borrower wants
        // adding 2.5% opnesea fee amount
        uint256 listingPrice = ((listingValueToBePaidToNiftyApes) * 40 + 38) / 39;

        address nftOwnerBefore = IERC721Upgradeable(offer.nftContractAddress).ownerOf(offer.nftId);
        uint256 sellOnSeaportAssetBalanceBeforeListing;
        uint256 borrower1BalanceBeforeListing;
        if (loanAuction.asset == ETH_ADDRESS) {
            sellOnSeaportAssetBalanceBeforeListing = address(sellOnSeaport).balance;
            borrower1BalanceBeforeListing = borrower1.balance;
        } else {
            sellOnSeaportAssetBalanceBeforeListing = IERC20Upgradeable(loanAuction.asset).balanceOf(address(sellOnSeaport));
            borrower1BalanceBeforeListing = IERC20Upgradeable(loanAuction.asset).balanceOf(borrower1);
        }
        assertEq(address(lending), nftOwnerBefore);

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

        ISeaport.Order memory order = _createOrder(
            offer.nftContractAddress,
            offer.nftId,
            listingPrice,
            loanAuction.loanEndTimestamp,
            loanAuction.asset
        );
        assertEq(orderHash, _getOrderHash(order));
        if (loanAuction.asset == ETH_ADDRESS) {
            vm.prank(users[0]);
            ISeaport(SEAPORT_ADDRESS).fulfillOrder{value: listingPrice}(order, bytes32(0));
        } else {
            mintDai(users[0], listingPrice);
            vm.startPrank(users[0]);
            ERC721Mock(loanAuction.asset).approve(SEAPORT_ADDRESS, listingPrice);
            ISeaport(SEAPORT_ADDRESS).fulfillOrder(order, bytes32(0));
            vm.stopPrank();
        }
        
        uint256 sellOnSeaportAssetBalanceAfterOrderFulfulling;
        if (loanAuction.asset == ETH_ADDRESS) {
            sellOnSeaportAssetBalanceAfterOrderFulfulling = address(sellOnSeaport).balance;
        } else {
            sellOnSeaportAssetBalanceAfterOrderFulfulling = IERC20Upgradeable(loanAuction.asset).balanceOf(address(sellOnSeaport));
        }
        assertEq( IERC721Upgradeable(offer.nftContractAddress).ownerOf(offer.nftId), users[0]);
        assertEq(sellOnSeaportAssetBalanceAfterOrderFulfulling - sellOnSeaportAssetBalanceBeforeListing, listingValueToBePaidToNiftyApes);

        if (lenderCall) {
            vm.startPrank(offer.creator);
        } else {
            vm.startPrank(borrower1);
        }
        sellOnSeaport.validateSaleAndWithdraw(offer.nftContractAddress, offer.nftId, orderHash);
        vm.stopPrank();

        uint256 sellOnSeaportAssetBalanceAfterWithdraw;
        uint256 borrower1BalanceAfterWithdraw;
        if (loanAuction.asset == ETH_ADDRESS) {
            sellOnSeaportAssetBalanceAfterWithdraw = address(sellOnSeaport).balance;
            borrower1BalanceAfterWithdraw = borrower1.balance;
        } else {
            sellOnSeaportAssetBalanceAfterWithdraw = IERC20Upgradeable(loanAuction.asset).balanceOf(address(sellOnSeaport));
            borrower1BalanceAfterWithdraw = IERC20Upgradeable(loanAuction.asset).balanceOf(borrower1);
        }
        loanAuction = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);

        assertEq(sellOnSeaportAssetBalanceAfterWithdraw, sellOnSeaportAssetBalanceBeforeListing);
        assertEq(borrower1BalanceAfterWithdraw - borrower1BalanceBeforeListing, profitForTheBorrower);
        assertEq(loanAuction.loanBeginTimestamp, 0);
    }

    function test_unit_validateSaleAndWithdraw_happy_case_ETH() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_validateSaleAndWithdraw_happy_case(fixedForSpeed, false);
    }

    function test_unit_validateSaleAndWithdraw_happy_case_DAI() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0;
        _test_unit_validateSaleAndWithdraw_happy_case(fixedForSpeed, false);
    }

    function test_fuzz_validateSaleAndWithdraw_happy_case(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        _test_unit_validateSaleAndWithdraw_happy_case(fuzzedOfferData, false);
    }

    function test_fuzz_validateSaleAndWithdraw_happy_case_lender_call(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        _test_unit_validateSaleAndWithdraw_happy_case(fuzzedOfferData, true);
    }

    function _test_unit_validateSaleAndWithdraw_notFulfilled_not_happy(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanAuction = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp) / 2);

        uint256 listingValueToBePaidToNiftyApes = _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, loanAuction.loanEndTimestamp);
        // adding 2.5% opnesea fee amount
        uint256 listingPrice = ((listingValueToBePaidToNiftyApes) * 40 + 38) / 39;

        vm.startPrank(borrower1);
        bytes32 orderHash = sellOnSeaport.listNftForSale(
            offer.nftContractAddress,
            offer.nftId,
            listingPrice,
            block.timestamp,
            loanAuction.loanEndTimestamp,
            1
        );

        vm.expectRevert("00063");
        sellOnSeaport.validateSaleAndWithdraw(offer.nftContractAddress, offer.nftId, orderHash);
        vm.stopPrank();
    }

    function test_fuzz_validateSaleAndWithdraw_notFulfilled_not_happy(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        _test_unit_validateSaleAndWithdraw_notFulfilled_not_happy(fuzzedOfferData);
    }
    
    function _createOrder(
        address nftContractAddress,
        uint256 nftId,
        uint256 listingPrice,
        uint256 listingEndTime,
        address asset
    ) internal view returns (ISeaport.Order memory order) {
        uint256 openseaFeeAmount = listingPrice - (listingPrice * 39) / 40;
        ISeaport.ItemType considerationItemType = (asset == ETH_ADDRESS ? ISeaport.ItemType.NATIVE : ISeaport.ItemType.ERC20);
        address considerationToken = (asset == ETH_ADDRESS ? address(0) : asset);

        order = ISeaport.Order(
            {
                parameters: ISeaport.OrderParameters(
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
                        totalOriginalConsiderationItems: 2
                    }
                ),
                signature: bytes("")
            }
        );
        order.parameters.offer[0] = ISeaport.OfferItem(
            {
                itemType: ISeaport.ItemType.ERC721,
                token: nftContractAddress,
                identifierOrCriteria: nftId,
                startAmount: 1,
                endAmount: 1
            }
        );
        order.parameters.consideration[0] = ISeaport.ConsiderationItem(
            {
                itemType: considerationItemType,
                token: considerationToken,
                identifierOrCriteria: 0,
                startAmount: listingPrice - openseaFeeAmount,
                endAmount:listingPrice - openseaFeeAmount,
                recipient: payable(address(sellOnSeaport))
            }
            
        );
        order.parameters.consideration[1] = ISeaport.ConsiderationItem(
            {
                itemType: considerationItemType,
                token: considerationToken,
                identifierOrCriteria: 0,
                startAmount: openseaFeeAmount,
                endAmount: openseaFeeAmount,
                recipient: payable(0x0000a26b00c1F0DF003000390027140000fAa719)
            }
        );
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

    function _getOrderHash(ISeaport.Order memory order) internal view returns (bytes32 orderHash) {
        // Derive order hash by supplying order parameters along with counter.
        orderHash = ISeaport(SEAPORT_ADDRESS).getOrderHash(
            ISeaport.OrderComponents(
                order.parameters.offerer,
                order.parameters.zone,
                order.parameters.offer,
                order.parameters.consideration,
                order.parameters.orderType,
                order.parameters.startTime,
                order.parameters.endTime,
                order.parameters.zoneHash,
                order.parameters.salt,
                order.parameters.conduitKey,
                ISeaport(SEAPORT_ADDRESS).getCounter(order.parameters.offerer)
            )
        );
    }
}
