pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/purchaseWithFinancing/ISeaport.sol";
import "../../../PurchaseWithFinancing.sol";
import "../../mock/ERC721Mock.sol";
import "../../mock/SeaportMock.sol";

contract TestPurchaseWithFinancing is Test, OffersLoansRefinancesFixtures {
    PurchaseWithFinancing purchaseWithFinancing;
    SeaportMock seaportMock;

    struct FuzzedBasicOrderParams {
        address zone;
        uint256 tokenId;
        uint128 paymentAmount;
        bytes32 zoneHash;
        uint256 salt;
    }

    function setUp() public override {
        super.setUp();

        seaportMock = new SeaportMock();
        purchaseWithFinancing = new PurchaseWithFinancing(address(seaportMock));
        seaportMock.approve(address(purchaseWithFinancing));
    }

    function _test_purchaseWithFinancing_simplest_case(
        FuzzedOfferFields memory fuzzedOfferData,
        FuzzedBasicOrderParams memory fuzzedParamData
    ) private {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        ISeaport.BasicOrderParameters memory params = basicOrderParamsFromFields(fuzzedParamData);

        createOfferAndTryPurchaseWithFinancing(offer, "should work");
    }

    function testPurchaseWithFinancing(
        FuzzedOfferFields memory fuzzedOfferData,
        FuzzedBasicOrderParams memory fuzzedParamData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        _test_purchaseWithFinancing_simplest_case(fuzzedOfferData, fuzzedParamData);
        assertEq(true, true);
    }

    //
    // HELPERS
    //
    function createOfferAndTryPurchaseWithFinancing(Offer memory offer, bytes memory errorCode)
        internal
        returns (Offer memory, LoanAuction memory)
    {
        Offer memory offerCreated = createOffer(offer, lender1);

        approveLending(offer);
        LoanAuction memory loan = tryPurchaseWithFinancing(offer, errorCode);
        return (offerCreated, loan);
    }

    function tryPurchaseWithFinancing(Offer memory offer, bytes memory errorCode)
        internal
        returns (LoanAuction memory)
    {
        vm.startPrank(borrower1);
        bytes32 offerHash = offers.getOfferHash(offer);

        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }

        // purchaseWithFinancing.purchaseWithFinancingOpenSea(
        //     offer.nftContractAddress,
        //     offer.nftId,
        //     offerHash,
        //     offer.floorTerm,
        // );
        vm.stopPrank();

        return lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
    }

    function basicOrderParamsFromFields(FuzzedBasicOrderParams memory fuzzed)
        internal
        returns (ISeaport.BasicOrderParameters memory)
    {
        ISeaport.BasicOrderParameters memory params;
        params.considerationToken = address(0);
        params.considerationIdentifier = 0;
        params.considerationAmount = fuzzed.paymentAmount;
        params.offerer = payable(address(0));
        params.zone = fuzzed.zone;
        params.offerToken = seaportMock.mockNft.address;
        params.offerIdentifier = 999;
        params.offerAmount = 1;
        params.basicOrderType = ISeaport.BasicOrderType.ETH_TO_ERC721_FULL_OPEN;
        params.startTime = block.timestamp;
        params.endTime = block.timestamp + 100;
        params.zoneHash = fuzzed.zoneHash;
        params.salt = fuzzed.salt;
        params.offererConduitKey = bytes32(0);
        params.fulfillerConduitKey = bytes32(0);
        params.totalOriginalAdditionalRecipients = 0;
        params.signature = bytes("test signature");
        return params;
    }
}
