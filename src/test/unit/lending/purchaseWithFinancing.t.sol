pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/niftyapes/purchaseWithFinancing/ISeaport.sol";
import "../../../PurchaseWithFinancing.sol";

contract TestPurchaseWithFinancing is Test, OffersLoansRefinancesFixtures {

    struct FuzzedBasicOrderParams {
        address zone;
        uint256 tokenId;
        uint128 paymentAmount;
        bytes32 zoneHash;
        uint256 salt;
    }

    function setUp() public override {
        super.setUp();
    }

    function _test_purchaseWithFinancing_simplest_case(
        FuzzedOfferFields memory fuzzedOfferData,
        FuzzedBasicOrderParams memory fuzzedParamData
    ) private {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        offer.nftContractAddress = seaportMock.mockNft.address;
        offer.nftId = 1;
        offer.asset = ETH_ADDRESS;
        ISeaport.BasicOrderParameters memory params = basicOrderParamsFromFields(fuzzedParamData);

        createOfferAndTryPurchaseWithFinancing(offer, params, "should work");
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
    function createOfferAndTryPurchaseWithFinancing(Offer memory offer, ISeaport.BasicOrderParameters memory params, bytes memory errorCode)
        internal
        returns (Offer memory, LoanAuction memory)
    {
        Offer memory offerCreated = createOffer(offer, lender1);

        approveLending(offer);
        LoanAuction memory loan = tryPurchaseWithFinancing(offer, params, errorCode);
        return (offerCreated, loan);
    }

    function tryPurchaseWithFinancing(Offer memory offer,
    ISeaport.BasicOrderParameters memory params,
    bytes memory errorCode)
        internal
        returns (LoanAuction memory)
    {
        vm.startPrank(borrower1);
        bytes32 offerHash = offers.getOfferHash(offer);

        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }
        console.log(offer.amount);
        console.log(params.considerationAmount);
        uint borrowerPays = params.considerationAmount - offer.amount;
        purchaseWithFinancing.purchaseWithFinancingOpenSea{value:borrowerPays}(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm,
            params
        );
        vm.stopPrank();

        return purchaseWithFinancing.getLoanAuction(offer.nftContractAddress, offer.nftId);
    }

    function basicOrderParamsFromFields(FuzzedBasicOrderParams memory fuzzed)
        internal
        returns (ISeaport.BasicOrderParameters memory)
    {
        ISeaport.BasicOrderParameters memory params;
        params.considerationToken = address(0);
        params.considerationIdentifier = 1;
        params.considerationAmount = 100 ether;
        params.offerer = payable(address(0));
        params.zone = fuzzed.zone;
        params.offerToken = seaportMock.mockNft.address;
        params.offerIdentifier = 1;
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
