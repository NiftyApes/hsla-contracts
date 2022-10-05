pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../../interfaces/seaport/ISeaport.sol";

contract TestSeaportPwfIntegration is Test, OffersLoansRefinancesFixtures, ERC721HolderUpgradeable {
    function setUp() public override {
        // pin block to time of writing test to reflect consistent state
        vm.rollFork(15510097);
        vm.warp(1662833943);

        super.setUp();
    }

    function _test_purchaseWithFinancing_simplest_case(
        Offer memory offer,
        ISeaport.Order memory order
    ) private {
        uint256 considerationAmount;

        for (uint256 i = 0; i < order.parameters.totalOriginalConsiderationItems; i++) {
            considerationAmount += order.parameters.consideration[i].endAmount;
        }

        offer.nftContractAddress = order.parameters.offer[0].token;
        offer.nftId = order.parameters.offer[0].identifierOrCriteria;
        if (order.parameters.consideration[0].token == address(0)) {
            offer.asset = ETH_ADDRESS;
        } else {
            offer.asset = order.parameters.consideration[0].token;
        }
        offer.amount = uint128(considerationAmount / 2);
        offer.expiration = uint32(block.timestamp + 1);

        (, LoanAuction memory loanAuction) = createOfferAndTryPurchaseWithFinancing(
            offer,
            order,
            "should work"
        );

        // lending contract has NFT
        assertEq(
            IERC721Upgradeable(offer.nftContractAddress).ownerOf(offer.nftId),
            address(lending)
        );
        // loan auction exists
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        // loan auction exists
        assertEq(loanAuction.nftOwner, borrower1);
        assertEq(loanAuction.amountDrawn, offer.amount);
    }

    function test_fuzz_PurchaseWithFinancing_simplest_case_ETH(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        ISeaport.Order memory order = createAndValidateETHOffer();

        _test_purchaseWithFinancing_simplest_case(offer, order);
    }

    function test_unit_PurchaseWithFinancing_simplest_case_ETH() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        ISeaport.Order memory order = createAndValidateETHOffer();

        _test_purchaseWithFinancing_simplest_case(offer, order);
    }

    function test_fuzz_PurchaseWithFinancing_simplest_case_DAI(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        ISeaport.Order memory order = createAndValidateDAIOffer();

        _test_purchaseWithFinancing_simplest_case(offer, order);
    }

    function test_unit_PurchaseWithFinancing_simplest_case_DAI() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        ISeaport.Order memory order = createAndValidateDAIOffer();

        _test_purchaseWithFinancing_simplest_case(offer, order);
    }

    //
    // HELPERS
    //
    function createOfferAndTryPurchaseWithFinancing(
        Offer memory offer,
        ISeaport.Order memory params,
        bytes memory errorCode
    ) internal returns (Offer memory, LoanAuction memory) {
        Offer memory offerCreated = createOffer(offer, lender1);

        LoanAuction memory loan = tryPurchaseWithFinancing(offer, params, errorCode);
        return (offerCreated, loan);
    }

    function tryPurchaseWithFinancing(
        Offer memory offer,
        ISeaport.Order memory order,
        bytes memory errorCode
    ) internal returns (LoanAuction memory) {
        vm.startPrank(borrower1);
        bytes32 offerHash = offers.getOfferHash(offer);

        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }
        uint256 borrowerPays = (uint256(offer.amount) * 2) - uint256(offer.amount);

        if (offer.asset == ETH_ADDRESS) {
            seaportPWF.purchaseWithFinancingSeaport{ value: borrowerPays }(
                offerHash,
                offer.floorTerm,
                order,
                bytes32(0)
            );
        } else {
            daiToken.approve(address(seaportPWF), borrowerPays);
            seaportPWF.purchaseWithFinancingSeaport(
                offerHash,
                offer.floorTerm,
                order,
                bytes32(0)
            );
        }
        vm.stopPrank();

        return lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
    }

    function toOrderComponents(ISeaport.OrderParameters memory _params, uint256 nonce)
        internal
        pure
        returns (ISeaport.OrderComponents memory)
    {
        return
            ISeaport.OrderComponents(
                _params.offerer,
                _params.zone,
                _params.offer,
                _params.consideration,
                _params.orderType,
                _params.startTime,
                _params.endTime,
                _params.zoneHash,
                _params.salt,
                _params.conduitKey,
                nonce
            );
    }

    function createAndValidateETHOffer() public returns (ISeaport.Order memory) {
        ISeaport.Order memory order = ETHOrder();

        address offerer = 0xf1BCf736a46D41f8a9d210777B3d75090860a665;
        bytes32 order_hash = 0x95a8fef9a007729a938410f6c7f4bdce07b929a2ef83979a84f53ec14dbda06b;

        vm.startPrank(borrower1);
        assertEq(
            order_hash,
            ISeaport(SEAPORT_ADDRESS).getOrderHash(
                toOrderComponents(order.parameters, ISeaport(SEAPORT_ADDRESS).getCounter(offerer))
            )
        );
        (bool valid, bool cancelled, uint256 filled, ) = ISeaport(SEAPORT_ADDRESS).getOrderStatus(
            order_hash
        );
        assertEq(valid, false);
        assertEq(cancelled, false);
        assertEq(filled, 0);
        vm.stopPrank();

        return order;
    }

    function createAndValidateDAIOffer() public returns (ISeaport.Order memory) {
        ISeaport.Order memory order = DAIOrder();

        address offerer = 0x061d56206E34796DbA53C491e89118e0baA6268A;
        bytes32 order_hash = 0x80032334edd1fd7f06d07103cd8b8b91e155b559e14e97e3c35111b007bc116f;

        vm.startPrank(borrower1);
        assertEq(
            order_hash,
            ISeaport(SEAPORT_ADDRESS).getOrderHash(
                toOrderComponents(order.parameters, ISeaport(SEAPORT_ADDRESS).getCounter(offerer))
            )
        );
        (bool valid, bool cancelled, uint256 filled, ) = ISeaport(SEAPORT_ADDRESS).getOrderStatus(
            order_hash
        );
        assertEq(valid, false);
        assertEq(cancelled, false);
        assertEq(filled, 0);
        vm.stopPrank();

        return order;
    }

    function ETHOrder() internal pure returns (ISeaport.Order memory) {
        ISeaport.Order memory order;
        order.parameters.offerer = address(0xf1BCf736a46D41f8a9d210777B3d75090860a665);
        order.parameters.zone = address(0x004C00500000aD104D7DBd00e3ae0A5C00560C00);
        order.parameters.offer = new ISeaport.OfferItem[](1);
        order.parameters.offer[0].itemType = ISeaport.ItemType.ERC721;
        order.parameters.offer[0].token = address(0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D);
        order.parameters.offer[0].identifierOrCriteria = 326;
        order.parameters.offer[0].startAmount = 1;
        order.parameters.offer[0].endAmount = 1;
        order.parameters.consideration = new ISeaport.ConsiderationItem[](3);
        order.parameters.consideration[0].itemType = ISeaport.ItemType.NATIVE;
        order.parameters.consideration[0].token = address(0);
        order.parameters.consideration[0].identifierOrCriteria = 0;
        order.parameters.consideration[0].startAmount = 73625000000000000000;
        order.parameters.consideration[0].endAmount = 73625000000000000000;
        order.parameters.consideration[0].recipient = payable(
            address(0xf1BCf736a46D41f8a9d210777B3d75090860a665)
        );
        order.parameters.consideration[1].itemType = ISeaport.ItemType.NATIVE;
        order.parameters.consideration[1].token = address(0);
        order.parameters.consideration[1].identifierOrCriteria = 0;
        order.parameters.consideration[1].startAmount = 1937500000000000000;
        order.parameters.consideration[1].endAmount = 1937500000000000000;
        order.parameters.consideration[1].recipient = payable(
            address(0x0000a26b00c1F0DF003000390027140000fAa719)
        );
        order.parameters.consideration[2].itemType = ISeaport.ItemType.NATIVE;
        order.parameters.consideration[2].token = address(0);
        order.parameters.consideration[2].identifierOrCriteria = 0;
        order.parameters.consideration[2].startAmount = 1937500000000000000;
        order.parameters.consideration[2].endAmount = 1937500000000000000;
        order.parameters.consideration[2].recipient = payable(
            address(0xA858DDc0445d8131daC4d1DE01f834ffcbA52Ef1)
        );
        order.parameters.orderType = ISeaport.OrderType.FULL_RESTRICTED;
        order.parameters.startTime = 1662306983;
        order.parameters.endTime = 1664820334;
        order.parameters.zoneHash = bytes32(
            0x0000000000000000000000000000000000000000000000000000000000000000
        );
        order.parameters.salt = 96789058676732069;
        order.parameters.conduitKey = bytes32(
            0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000
        );
        order.parameters.totalOriginalConsiderationItems = 3;
        order.signature = bytes(
            hex"0fd8072572bdec4b6f496cef4380c1fde6aa43f0fc9c0c89b3df988195d1cfc047cdc65045bc836e3238a1f9d2ac074e0d7a7e74f646f6b0ed23339f780680131b"
        );
        return order;
    }

    function DAIOrder() internal pure returns (ISeaport.Order memory) {
        ISeaport.Order memory order;
        order.parameters.offerer = address(0x061d56206E34796DbA53C491e89118e0baA6268A);
        order.parameters.zone = address(0x004C00500000aD104D7DBd00e3ae0A5C00560C00);
        order.parameters.offer = new ISeaport.OfferItem[](1);
        order.parameters.offer[0].itemType = ISeaport.ItemType.ERC721;
        order.parameters.offer[0].token = address(0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85);
        order
            .parameters
            .offer[0]
            .identifierOrCriteria = 112775308845248705605204627335822260349900599385038464061504005475211094768304;
        order.parameters.offer[0].startAmount = 1;
        order.parameters.offer[0].endAmount = 1;
        order.parameters.consideration = new ISeaport.ConsiderationItem[](2);
        order.parameters.consideration[0].itemType = ISeaport.ItemType.ERC20;
        order.parameters.consideration[0].token = address(
            0x6B175474E89094C44Da98b954EedeAC495271d0F
        );
        order.parameters.consideration[0].identifierOrCriteria = 0;
        order.parameters.consideration[0].startAmount = 146250000000000000000;
        order.parameters.consideration[0].endAmount = 146250000000000000000;
        order.parameters.consideration[0].recipient = payable(
            address(0x061d56206E34796DbA53C491e89118e0baA6268A)
        );
        order.parameters.consideration[1].itemType = ISeaport.ItemType.ERC20;
        order.parameters.consideration[1].token = address(
            0x6B175474E89094C44Da98b954EedeAC495271d0F
        );
        order.parameters.consideration[1].identifierOrCriteria = 0;
        order.parameters.consideration[1].startAmount = 3750000000000000000;
        order.parameters.consideration[1].endAmount = 3750000000000000000;
        order.parameters.consideration[1].recipient = payable(
            address(0x0000a26b00c1F0DF003000390027140000fAa719)
        );
        order.parameters.orderType = ISeaport.OrderType.FULL_RESTRICTED;
        order.parameters.startTime = 1661919543;
        order.parameters.endTime = 1664597943;
        order.parameters.zoneHash = bytes32(
            0x0000000000000000000000000000000000000000000000000000000000000000
        );
        order.parameters.salt = 22072998211896108;
        order.parameters.conduitKey = bytes32(
            0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000
        );
        order.parameters.totalOriginalConsiderationItems = 2;
        order.signature = bytes(
            hex"3cae816f76b41b088e9849a0e3bc4f631866e657ecb1402f88b8ae9126f825956614f90d93dabeb45333232bf3e6a4b3ffa11ef07eeb34aed31e8c1ba3c1d5131b"
        );
        return order;
    }
}
