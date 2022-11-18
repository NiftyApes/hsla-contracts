// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "../../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../mock/FlashSellReceiverMock.sol";
import "../../../../interfaces/niftyapes/lending/ILendingStructs.sol";

contract TestSellOnSeaportWithFlashSell is Test, ILendingStructs, OffersLoansRefinancesFixtures {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    function setUp() public override {
        // pin block to time of writing test to reflect consistent state
        vm.rollFork(15510097);
        vm.warp(1662833943);
        super.setUp();
    }

    function _test_unit_SellOnSeaportExecuteOperation_simplest_case(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanBefore = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loanBefore.loanEndTimestamp - loanBefore.loanBeginTimestamp) / 10);

        uint256 minValueRequiredToCloseTheLoan = _calculateTotalLoanPaymentAmountAtTimestamp(loanBefore, block.timestamp);
        uint256 profitForTheBorrower = 1 ether; // assume any profit the borrower wants
        // adding 2.5% opnesea fee amount
        uint256 bidPrice = ((minValueRequiredToCloseTheLoan + profitForTheBorrower) * 40 + 38) / 39;

        ISeaport.Order[] memory order = _createOrder(
            offer.nftContractAddress,
            offer.nftId,
            bidPrice,
            loanBefore.asset,
            users[0]
        );

        if (loanBefore.asset == ETH_ADDRESS) {
            mintWeth(users[0], bidPrice);
        } else {
            mintDai(users[0], bidPrice);
        }

        vm.startPrank(users[0]);
        IERC20Upgradeable(order[0].parameters.offer[0].token).approve(0x1E0049783F008A0085193E00003D00cd54003c71, bidPrice);
        ISeaport(SEAPORT_ADDRESS).validate(order);
        vm.stopPrank();

        (bool valid,,,)  = ISeaport(SEAPORT_ADDRESS).getOrderStatus(_getOrderHash(order[0]));
        assertEq(valid, true);

        address nftOwnerBefore = IERC721Upgradeable(offer.nftContractAddress).ownerOf(offer.nftId);
        uint256 borrower1AssetBalanceBefore;
        if (loanBefore.asset == ETH_ADDRESS) {
            borrower1AssetBalanceBefore = address(borrower1).balance;
        } else {
            borrower1AssetBalanceBefore = IERC20Upgradeable(loanBefore.asset).balanceOf(address(borrower1));
        }

        vm.startPrank(borrower1);
        flashSell.borrowNFTForSale(
            offer.nftContractAddress,
            offer.nftId,
            address(sellOnSeaport),
            abi.encode(order[0], bytes32(0))
        );
        vm.stopPrank();

        LoanAuction memory loanAfter = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        address nftOwnerAfter = IERC721Upgradeable(offer.nftContractAddress).ownerOf(offer.nftId);
        uint256 borrower1AssetBalanceAfter;
        if (loanBefore.asset == ETH_ADDRESS) {
            borrower1AssetBalanceAfter = address(borrower1).balance;
        } else {
            borrower1AssetBalanceAfter = IERC20Upgradeable(loanBefore.asset).balanceOf(address(borrower1));
        }
        assertEq(address(lending), nftOwnerBefore);
        assertEq(address(users[0]), nftOwnerAfter);
        assertEq(borrower1AssetBalanceAfter - borrower1AssetBalanceBefore, profitForTheBorrower);
        assertEq(loanAfter.loanBeginTimestamp, 0);
    }

    function test_unit_SellOnSeaportExecuteOperation_simplest_case_ETH() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_SellOnSeaportExecuteOperation_simplest_case(fixedForSpeed);
    }

    function test_fuzz_SellOnSeaportExecuteOperation_simplest_case_ETH(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        fuzzedOfferData.randomAsset = 1;
        fuzzedOfferData.amount = fuzzedOfferData.amount / 1000;
        _test_unit_SellOnSeaportExecuteOperation_simplest_case(fuzzedOfferData);
    }

    function test_unit_SellOnSeaportExecuteOperation_simplest_case_DAI() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0;
        _test_unit_SellOnSeaportExecuteOperation_simplest_case(fixedForSpeed);
    }

    function test_fuzz_SellOnSeaportExecuteOperation_simplest_case_DAI(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        fuzzedOfferData.randomAsset = 0;
        _test_unit_SellOnSeaportExecuteOperation_simplest_case(fuzzedOfferData);
    }

    function _test_unit_cannot_SellOnSeaportExecuteOperation_invalidOrderToken(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loan = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loan.loanEndTimestamp - loan.loanBeginTimestamp) / 10);

        uint256 minValueRequiredToCloseTheLoan = _calculateTotalLoanPaymentAmountAtTimestamp(loan, block.timestamp);
        // adding 2.5% opnesea fee amount
        uint256 bidPrice = ((minValueRequiredToCloseTheLoan) * 40 + 38) / 39;

        ISeaport.Order[] memory order = _createOrder(
            offer.nftContractAddress,
            offer.nftId,
            bidPrice,
            loan.asset,
            users[0]
        );

        if (loan.asset == ETH_ADDRESS) {
            mintWeth(users[0], bidPrice);
        } else {
            mintDai(users[0], bidPrice);
        }

        vm.startPrank(users[0]);
        order[0].parameters.offer[0].token = address(0xabcd);
        ISeaport(SEAPORT_ADDRESS).validate(order);
        vm.stopPrank();

        (bool valid,,,)  = ISeaport(SEAPORT_ADDRESS).getOrderStatus(_getOrderHash(order[0]));
        assertEq(valid, true);

        vm.startPrank(borrower1);
        vm.expectRevert("00067");
        flashSell.borrowNFTForSale(
            offer.nftContractAddress,
            offer.nftId,
            address(sellOnSeaport),
            abi.encode(order[0], bytes32(0))
        );
        vm.stopPrank();
    }

    function _test_unit_cannot_SellOnSeaportExecuteOperation_invalidOrderAmount(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loan = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loan.loanEndTimestamp - loan.loanBeginTimestamp) / 10);

        uint256 minValueRequiredToCloseTheLoan = _calculateTotalLoanPaymentAmountAtTimestamp(loan, block.timestamp);
        // adding 2.5% opnesea fee amount
        uint256 bidPrice = ((minValueRequiredToCloseTheLoan) * 40 + 38) / 39;

        ISeaport.Order[] memory order = _createOrder(
            offer.nftContractAddress,
            offer.nftId,
            bidPrice - 1,
            loan.asset,
            users[0]
        );

        if (loan.asset == ETH_ADDRESS) {
            mintWeth(users[0], bidPrice);
        } else {
            mintDai(users[0], bidPrice);
        }

        vm.startPrank(users[0]);
        IERC20Upgradeable(order[0].parameters.offer[0].token).approve(0x1E0049783F008A0085193E00003D00cd54003c71, bidPrice);
        ISeaport(SEAPORT_ADDRESS).validate(order);
        vm.stopPrank();

        (bool valid,,,)  = ISeaport(SEAPORT_ADDRESS).getOrderStatus(_getOrderHash(order[0]));
        assertEq(valid, true);

        vm.startPrank(borrower1);
        vm.expectRevert("00066");
        flashSell.borrowNFTForSale(
            offer.nftContractAddress,
            offer.nftId,
            address(sellOnSeaport),
            abi.encode(order[0], bytes32(0))
        );
        vm.stopPrank();
    }

    function test_unit_cannot_SellOnSeaportExecuteOperation_invalidOrderToken() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cannot_SellOnSeaportExecuteOperation_invalidOrderToken(fixedForSpeed);
    }

    function test_unit_cannot_SellOnSeaportExecuteOperation_invalidOrderAmount() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cannot_SellOnSeaportExecuteOperation_invalidOrderAmount(fixedForSpeed);
    }

    function _createOrder(
        address nftContractAddress,
        uint256 nftId,
        uint256 bidPrice,
        address asset,
        address orderCreator
    ) internal view returns (ISeaport.Order[] memory order) {
        uint256 seaportFeeAmount = bidPrice - (bidPrice * 39) / 40;
        ISeaport.ItemType offerItemType = ISeaport.ItemType.ERC20;
        address offerToken = (asset == ETH_ADDRESS ? address(wethToken) : asset);

        order = new ISeaport.Order[](1);
        order[0] = ISeaport.Order(
            {
                parameters: ISeaport.OrderParameters(
                    {
                        offerer: payable(orderCreator),
                        zone: 0x004C00500000aD104D7DBd00e3ae0A5C00560C00,
                        offer: new ISeaport.OfferItem[](1),
                        consideration: new ISeaport.ConsiderationItem[](2),
                        orderType: ISeaport.OrderType.FULL_OPEN,
                        startTime: block.timestamp,
                        endTime: block.timestamp + 24*60*60,
                        zoneHash: bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                        salt: 1,
                        conduitKey: bytes32(0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000),
                        totalOriginalConsiderationItems: 2
                    }
                ),
                signature: bytes("")
            }
        );
        order[0].parameters.offer[0] = ISeaport.OfferItem(
            {
                itemType: offerItemType,
                token: offerToken,
                identifierOrCriteria: 0,
                startAmount: bidPrice,
                endAmount: bidPrice
            }
        );
        order[0].parameters.consideration[0] = ISeaport.ConsiderationItem(
            {
                itemType: ISeaport.ItemType.ERC721,
                token: nftContractAddress,
                identifierOrCriteria: nftId,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(orderCreator)
            }
        );
        order[0].parameters.consideration[1] = ISeaport.ConsiderationItem(
            {
                itemType: offerItemType,
                token: offerToken,
                identifierOrCriteria: 0,
                startAmount: seaportFeeAmount,
                endAmount: seaportFeeAmount,
                recipient: payable(0x0000a26b00c1F0DF003000390027140000fAa719)
            }
        );
    }

    function _calculateTotalLoanPaymentAmount(
        address nftContractAddress,
        uint256 nftId,
        LoanAuction memory loanAuction
        ) private view returns(uint256) {
        uint256 interestThresholdDelta = 
            lending.checkSufficientInterestAccumulated(
                nftContractAddress,
                nftId
            );

        (uint256 lenderInterest, uint256 protocolInterest) = 
            lending.calculateInterestAccrued(
                nftContractAddress,
                nftId
            );

        return uint256(loanAuction.accumulatedLenderInterest) +
                loanAuction.accumulatedPaidProtocolInterest +
                loanAuction.unpaidProtocolInterest +
                loanAuction.slashableLenderInterest +
                loanAuction.amountDrawn +
                interestThresholdDelta +
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

    function _calculateTotalLoanPaymentAmountAtTimestamp(
        LoanAuction memory loanAuction,
        uint256 timestamp
        ) internal view returns(uint256) {

        uint256 timePassed = timestamp - loanAuction.lastUpdatedTimestamp;

        uint256 lenderInterest = (timePassed * loanAuction.interestRatePerSecond);
        uint256 protocolInterest = (timePassed * loanAuction.protocolInterestRatePerSecond);

        uint256 interestThreshold;
        if (loanAuction.loanEndTimestamp - 1 days > uint32(timestamp)) {
            interestThreshold = (uint256(loanAuction.amountDrawn) * lending.gasGriefingPremiumBps()) /
                10_000;
        }

        lenderInterest = lenderInterest > interestThreshold ? lenderInterest : interestThreshold;

        return loanAuction.accumulatedLenderInterest +
            loanAuction.accumulatedPaidProtocolInterest +
            loanAuction.unpaidProtocolInterest +
            loanAuction.slashableLenderInterest +
            loanAuction.amountDrawn +
            lenderInterest +
            protocolInterest;
    }
}