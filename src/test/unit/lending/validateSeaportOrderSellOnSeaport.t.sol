// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../../interfaces/niftyapes/lending/ILendingEvents.sol";

contract TestCancelOrderSellOnSeaport is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function test_cannot_unit_validateSeaportOrderSellOnSeaport_notSellOnSeaport() public {
        
        ISeaport.Order[] memory orders = new ISeaport.Order[](1);
        orders[0] = ISeaport.Order(
            {
                parameters: ISeaport.OrderParameters(
                    {
                        offerer: address(lending),
                        zone: 0x004C00500000aD104D7DBd00e3ae0A5C00560C00,
                        offer: new ISeaport.OfferItem[](1),
                        consideration: new ISeaport.ConsiderationItem[](2),
                        orderType: ISeaport.OrderType.FULL_OPEN,
                        startTime: block.timestamp,
                        endTime: block.timestamp,
                        zoneHash: bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                        salt: 1,
                        conduitKey: bytes32(0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000),
                        totalOriginalConsiderationItems: 2
                    }
                ),
                signature: bytes("")
            }
        );

        vm.startPrank(borrower1);
        vm.expectRevert("00031");
        lending.validateSeaportOrderSellOnSeaport(SEAPORT_ADDRESS, orders);
        vm.stopPrank();
    }
}
