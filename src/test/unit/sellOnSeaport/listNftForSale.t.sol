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

    function _test_unit_listNftForSale_happy_case(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanAuction = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp) / 2);

        
        uint256 listingValueToBePaidToNiftyApes = _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, loanAuction.loanEndTimestamp);
        // taking the ceil of totalLoanAmount * 40 / 39 (basically adding 2.5% opnesea fee amount)
        uint256 listingPrice = (listingValueToBePaidToNiftyApes * 40 + 38) / 39;

        address nftOwnerBefore = IERC721Upgradeable(offer.nftContractAddress).ownerOf(offer.nftId);
        uint256 sellOnSeaportAssetBalanceBefore;
        if (loanAuction.asset == ETH_ADDRESS) {
            sellOnSeaportAssetBalanceBefore = address(sellOnSeaport).balance;
        } else {
            sellOnSeaportAssetBalanceBefore = IERC20Upgradeable(loanAuction.asset).balanceOf(address(sellOnSeaport));
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

        (bool valid, bool cancelled,,)  = ISeaport(SEAPORT_ADDRESS).getOrderStatus(orderHash);
        assertEq(valid, true);
        assertEq(cancelled, false);

        ISeaport.Order memory order = _createOrder(
            offer.nftContractAddress,
            offer.nftId,
            listingPrice,
            loanAuction.loanEndTimestamp,
            loanAuction.asset
        );
        bytes32 orderHashCreated = _getOrderHash(order);
        assertEq(orderHash, orderHashCreated);
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
        
        address nftOwnerAfter = IERC721Upgradeable(offer.nftContractAddress).ownerOf(offer.nftId);
        uint256 sellOnSeaportAssetBalanceAfter;
        if (loanAuction.asset == ETH_ADDRESS) {
            sellOnSeaportAssetBalanceAfter = address(sellOnSeaport).balance;
        } else {
            sellOnSeaportAssetBalanceAfter = IERC20Upgradeable(loanAuction.asset).balanceOf(address(sellOnSeaport));
        }
        assertEq(nftOwnerAfter, users[0]);
        assertEq(sellOnSeaportAssetBalanceAfter - sellOnSeaportAssetBalanceBefore , listingValueToBePaidToNiftyApes);
    }

    function test_unit_listNftForSale_happy_case_ETH() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_listNftForSale_happy_case(fixedForSpeed);
    }

    function test_unit_listNftForSale_happy_case_DAI() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0;
        _test_unit_listNftForSale_happy_case(fixedForSpeed);
    }

    function test_fuzz_listNftForSale_happy_case(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        _test_unit_listNftForSale_happy_case(fuzzedOfferData);
    }
    function _test_unit_cannot_listNftForSale_listingPriceInsufficient(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanAuction = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp) / 2);

        uint256 listingValueToBePaidToNiftyApes = _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, loanAuction.loanEndTimestamp);
        // taking the ceil of totalLoanAmount * 40 / 39 (basically adding 2.5% opnesea fee amount)
        uint256 listingPrice = (listingValueToBePaidToNiftyApes * 40 + 38) / 39;
        vm.startPrank(borrower1);
        vm.expectRevert("00060");
        sellOnSeaport.listNftForSale(
            offer.nftContractAddress,
            offer.nftId,
            listingPrice - 1,
            block.timestamp,
            loanAuction.loanEndTimestamp,
            1
        );
        vm.stopPrank();
    }

    function test_unit_cannot_listNftForSale_listingPriceInsufficient() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cannot_listNftForSale_listingPriceInsufficient(fixedForSpeed);
    }

    function test_fuzz_cannot_listNftForSale_listingPriceInsufficient(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        _test_unit_cannot_listNftForSale_listingPriceInsufficient(fuzzedOfferData);
    }

    function _test_unit_cannot_listNftForSale_callerNotBorrower(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanAuction = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loanAuction.loanEndTimestamp - loanAuction.loanBeginTimestamp) / 2);

        uint256 listingValueToBePaidToNiftyApes = _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, loanAuction.loanEndTimestamp);
        // taking the ceil of totalLoanAmount * 40 / 39 (basically adding 2.5% opnesea fee amount)
        uint256 listingPrice = (listingValueToBePaidToNiftyApes * 40 + 38) / 39;
        vm.startPrank(borrower2);
        vm.expectRevert("00021");
        sellOnSeaport.listNftForSale(
            offer.nftContractAddress,
            offer.nftId,
            listingPrice,
            block.timestamp,
            loanAuction.loanEndTimestamp,
            1
        );
        vm.stopPrank();
    }

    function test_unit_cannot_listNftForSale_callerNotBorrower() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cannot_listNftForSale_callerNotBorrower(fixedForSpeed);
    }

    function test_fuzz_cannot_listNftForSale_callerNotBorrower(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        _test_unit_cannot_listNftForSale_callerNotBorrower(fuzzedOfferData);
    }

    function _createOrder(
        address nftContractAddress,
        uint256 nftId,
        uint256 listingPrice,
        uint256 listingEndTime,
        address asset
    ) internal view returns (ISeaport.Order memory order) {
        uint256 seaportFeeAmount = listingPrice - (listingPrice * 39) / 40;
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
                startAmount: listingPrice - seaportFeeAmount,
                endAmount:listingPrice - seaportFeeAmount,
                recipient: payable(address(sellOnSeaport))
            }
            
        );
        order.parameters.consideration[1] = ISeaport.ConsiderationItem(
            {
                itemType: considerationItemType,
                token: considerationToken,
                identifierOrCriteria: 0,
                startAmount: seaportFeeAmount,
                endAmount: seaportFeeAmount,
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
