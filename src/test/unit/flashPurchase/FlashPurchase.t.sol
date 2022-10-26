pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/offers/IOffersStructs.sol";
import "../../mock/FlashPurchaseReceiverMock.sol";

contract TestFlashPurchase is Test, OffersLoansRefinancesFixtures, ERC721HolderUpgradeable {
    function setUp() public override {
        // pin block to time of writing test to reflect consistent state
        vm.rollFork(15617130);

        super.setUp();
    }

    function _test_flashPurchase_borrow_simplest_case(
        Offer memory offer,
        address nftContractAddress,
        uint256 nftId,
        address receiver,
        address asset,
        bool withSignature
    ) private {
        offer.nftContractAddress = nftContractAddress;
        offer.nftId = nftId;

        offer.asset = asset;

        offer.amount = 1 ether;
        offer.expiration = uint32(block.timestamp + 1);
        LoanAuction memory loanAuction;
        if (!withSignature) {
            loanAuction = createOfferAndTryBorrowingWithFlashPurchase(
                offer,
                nftId,
                receiver,
                "should work"
            );
        } else {
            loanAuction = signOfferAndTryBorrowingWithFlashPurchase(
                offer,
                nftId,
                receiver,
                "should work"
            );
        }
        

        // lending contract has NFT
        assertEq(
            IERC721Upgradeable(offer.nftContractAddress).ownerOf(nftId),
            address(lending)
        );
        // loan auction exists
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        // loan auction exists
        assertEq(loanAuction.nftOwner, borrower1);
        assertEq(loanAuction.amountDrawn, offer.amount);
        // receiver has the correct lending amount
        if (offer.asset == ETH_ADDRESS) {
            assertEq(
                address(receiver).balance,
                offer.amount
            );
        } else {
            assertEq(
                IERC20Upgradeable(offer.asset).balanceOf(receiver),
                offer.amount
            );
        }
    }

    function test_fuzz_flashPurchase_borrow_simplest_case_ETH(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        (address nftContractAddress, uint256 nftId, address receiver) = createReceiverWithOfferNFT();

        _test_flashPurchase_borrow_simplest_case(offer, nftContractAddress, nftId, receiver, ETH_ADDRESS, false);
    }

    function test_unit_flashPurchase_borrow_simplest_case_ETH() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (address nftContractAddress, uint256 nftId, address receiver) = createReceiverWithOfferNFT();

        _test_flashPurchase_borrow_simplest_case(offer, nftContractAddress, nftId, receiver, ETH_ADDRESS, false);
    }

    function test_fuzz_flashPurchase_borrow_simplest_case_DAI(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
    (address nftContractAddress, uint256 nftId, address receiver) = createReceiverWithOfferNFT();

        _test_flashPurchase_borrow_simplest_case(offer, nftContractAddress, nftId, receiver, address(daiToken), false);
    }

    function test_unit_flashPurchase_borrow_simplest_case_DAI() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (address nftContractAddress, uint256 nftId, address receiver) = createReceiverWithOfferNFT();

        _test_flashPurchase_borrow_simplest_case(offer, nftContractAddress, nftId, receiver, address(daiToken), false);
    }

    function test_fuzz_flashPurchase_borrowSignature_simplest_case_ETH(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        (address nftContractAddress, uint256 nftId, address receiver) = createReceiverWithOfferNFT();

        _test_flashPurchase_borrow_simplest_case(offer, nftContractAddress, nftId, receiver, ETH_ADDRESS, true);
    }

    function test_unit_flashPurchase_borrowSignature_simplest_case_ETH() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (address nftContractAddress, uint256 nftId, address receiver) = createReceiverWithOfferNFT();

        _test_flashPurchase_borrow_simplest_case(offer, nftContractAddress, nftId, receiver, ETH_ADDRESS, true);
    }

    function test_fuzz_flashPurchase_borrowSignature_simplest_case_DAI(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
    (address nftContractAddress, uint256 nftId, address receiver) = createReceiverWithOfferNFT();

        _test_flashPurchase_borrow_simplest_case(offer, nftContractAddress, nftId, receiver, address(daiToken), true);
    }

    function test_unit_flashPurchase_borrowSignature_simplest_case_DAI() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (address nftContractAddress, uint256 nftId, address receiver) = createReceiverWithOfferNFT();

        _test_flashPurchase_borrow_simplest_case(offer, nftContractAddress, nftId, receiver, address(daiToken), true);
    }

    //
    // HELPERS
    //
    function createOfferAndTryBorrowingWithFlashPurchase(
        Offer memory offer,
        uint256 nftId,
        address receiver,
        bytes memory errorCode
    ) internal returns (LoanAuction memory) {
        createOffer(offer, lender1);

        LoanAuction memory loan = tryBorrowingWithFlashPurchase(offer, nftId, receiver, errorCode);
        return loan;
    }

    function signOfferAndTryBorrowingWithFlashPurchase(
        Offer memory offer,
        uint256 nftId,
        address receiver,
        bytes memory errorCode
    ) internal returns (LoanAuction memory) {
        bytes memory signature = signOffer(lender1_private_key, offer);

        LoanAuction memory loan = tryBorrowingWithSignatureFlashPurchase(offer, signature, nftId, receiver, errorCode);
        return loan;
    }

    function tryBorrowingWithFlashPurchase(
        Offer memory offer,
        uint256 nftId,
        address receiver,
        bytes memory errorCode
    ) internal returns (LoanAuction memory) {
        vm.startPrank(borrower1);
        bytes32 offerHash = offers.getOfferHash(offer);

        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }
        flashPurchase.borrowFundsForPurchase(
            offerHash,
            offer.nftContractAddress,
            nftId,
            offer.floorTerm,
            receiver,
            borrower1,
            bytes("")
        );
        vm.stopPrank();

        return lending.getLoanAuction(offer.nftContractAddress, nftId);
    }

    function tryBorrowingWithSignatureFlashPurchase(
        Offer memory offer,
        bytes memory signature,
        uint256 nftId,
        address receiver,
        bytes memory errorCode
    ) internal returns (LoanAuction memory) {
        vm.startPrank(borrower1);
        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }

        flashPurchase.borrowSignature(
            offer,
            signature,
            nftId,
            receiver,
            borrower1,
            bytes("")
        );
        vm.stopPrank();

        return lending.getLoanAuction(offer.nftContractAddress, nftId);
    }

    function createReceiverWithOfferNFT() public returns (address, uint256, address) {
        address receiver = address(new FlashPurchaseReceiverMock());
        
        address _PUDGY_PENGUIN_CONTRACT_ADDRESS = 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8;
        address _PUDGY1_OWNER = 0x2cbC202392C0F0C846Bf028777a5e9B4e49D9FaC;

        vm.prank(_PUDGY1_OWNER);
        ERC721Mock(_PUDGY_PENGUIN_CONTRACT_ADDRESS).safeTransferFrom(_PUDGY1_OWNER, receiver, 1);
        return (_PUDGY_PENGUIN_CONTRACT_ADDRESS, 1, receiver);
    }
}
