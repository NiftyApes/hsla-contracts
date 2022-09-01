pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../../interfaces/seaport/ISeaport.sol";
import "../../../PurchaseWithFinancing.sol";
import "forge-std/Test.sol";

contract TestPurchaseWithFinancing is Test, OffersLoansRefinancesFixtures, ERC721HolderUpgradeable {
    function setUp() public override {
        super.setUp();

        // pin block to time of writing test to reflect consistent state
        // vm.rollFork(15455075);
        vm.warp(1664587837 - 100);

        // adjust tests to operate on consistent ETH and DAI on specific NFTs
    }

    function _test_purchaseWithFinancing_simplest_case(FuzzedOfferFields memory fuzzedOfferData)
        private
    {
        console.log("here 1");
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        console.log("here 1.1");
        ISeaport.BasicOrderParameters memory params = basicETHOrderParamsFromFields();

        console.log("here 2");

        offer.nftContractAddress = params.offerToken;
        offer.nftId = params.offerIdentifier;
        offer.asset = ETH_ADDRESS;
        offer.amount = uint128(params.considerationAmount / 2);
        offer.expiration = uint32(block.timestamp + 1);

        (, LoanAuction memory loanAuction) = createOfferAndTryPurchaseWithFinancing(
            offer,
            params,
            "should work"
        );

        console.log("here 3");

        // lending contract has NFT
        assertEq(
            IERC721Upgradeable(params.offerToken).ownerOf(params.offerIdentifier),
            address(lending)
        );
        // loan auction exists
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
    }

    function test_fuzz_PurchaseWithFinancing_simplest_case(FuzzedOfferFields memory fuzzedOfferData)
        public
        validateFuzzedOfferFields(fuzzedOfferData)
    {
        _test_purchaseWithFinancing_simplest_case(fuzzedOfferData);
    }

    function test_unit_PurchaseWithFinancing_simplest_case() public {
        _test_purchaseWithFinancing_simplest_case(defaultFixedFuzzedFieldsForFastUnitTesting);
    }

    //
    // HELPERS
    //
    function createOfferAndTryPurchaseWithFinancing(
        Offer memory offer,
        ISeaport.BasicOrderParameters memory params,
        bytes memory errorCode
    ) internal returns (Offer memory, LoanAuction memory) {
        Offer memory offerCreated = createOffer(offer, lender1);

        console.log("here 4");

        LoanAuction memory loan = tryPurchaseWithFinancing(offer, params, errorCode);
        return (offerCreated, loan);
    }

    function tryPurchaseWithFinancing(
        Offer memory offer,
        ISeaport.BasicOrderParameters memory params,
        bytes memory errorCode
    ) internal returns (LoanAuction memory) {
        vm.startPrank(borrower1);
        bytes32 offerHash = offers.getOfferHash(offer);

        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }
        uint256 borrowerPays = params.considerationAmount - uint256(offer.amount);

        if (offer.asset == ETH_ADDRESS) {
            console.log("here 5");

            purchaseWithFinancing.purchaseWithFinancingSeaport{ value: borrowerPays }(
                offer.nftContractAddress,
                offerHash,
                offer.floorTerm,
                params
            );
            console.log("here 6");
        } else {
            daiToken.approve(address(purchaseWithFinancing), borrowerPays);
            purchaseWithFinancing.purchaseWithFinancingSeaport(
                offer.nftContractAddress,
                offerHash,
                offer.floorTerm,
                params
            );
        }
        vm.stopPrank();

        return lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
    }

    function basicETHOrderParamsFromFields()
        internal
        returns (ISeaport.BasicOrderParameters memory)
    {
        ISeaport.BasicOrderParameters memory params;
        params.considerationToken = address(0);
        params.considerationIdentifier = 0;
        params.considerationAmount = 80 ether;
        params.offerer = payable(address(0xb2C0b589fa31B7c776aa6F7d4f231255cB0Fe373));
        params.zone = address(0x004C00500000aD104D7DBd00e3ae0A5C00560C00);
        params.offerToken = address(0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D);
        params.offerIdentifier = 9719;
        params.offerAmount = 1;
        params.basicOrderType = ISeaport.BasicOrderType.ETH_TO_ERC721_FULL_OPEN;
        params.startTime = 1661995837;
        params.endTime = 1664587837;
        params.zoneHash = bytes32(
            0x0000000000000000000000000000000000000000000000000000000000000000
        );
        params.salt = 14181645366604922;
        params.offererConduitKey = bytes32(
            0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000
        );
        params.fulfillerConduitKey = bytes32(0);
        params.totalOriginalAdditionalRecipients = 2;
        params.additionalRecipients = new ISeaport.AdditionalRecipient[](2);
        params.additionalRecipients[0].amount = 0.2 ether;
        params.additionalRecipients[0].recipient = payable(
            address(0x0000a26b00c1F0DF003000390027140000fAa719)
        );
        params.additionalRecipients[1].amount = 0.2 ether;
        params.additionalRecipients[1].recipient = payable(
            address(0xA858DDc0445d8131daC4d1DE01f834ffcbA52Ef1)
        );
        params.signature = bytes(
            "0xede1357d160d0111a96d3fcfd13c9cab4949c3282724b5e4108ae66616db02a51ad9ba42e0a41d16ebf586ce09b4435d81a627bb84dfe28c62123c7c0de8429e1c"
        );
        return params;
    }
}
