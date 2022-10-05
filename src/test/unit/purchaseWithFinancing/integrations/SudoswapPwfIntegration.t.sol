pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../../interfaces/niftyapes/offers/IOffersStructs.sol";

contract TestSudoswapPwfIntegration is Test, OffersLoansRefinancesFixtures, ERC721HolderUpgradeable {
    function setUp() public override {
        // pin block to time of writing test to reflect consistent state
        vm.rollFork(15617130);

        super.setUp();
    }

    function _test_purchaseWithFinancing_simplest_case(
        Offer memory offer,
        ILSSVMPair lssvmPair,
        uint256 nftId
    ) private {
        address nftContractAddress = address(lssvmPair.nft());
        offer.nftContractAddress = nftContractAddress;
        offer.nftId = nftId;

        ILSSVMPairFactoryLike.PairVariant pairVariant = lssvmPair.pairVariant();
        if (pairVariant == ILSSVMPairFactoryLike.PairVariant.ENUMERABLE_ERC20 || pairVariant == ILSSVMPairFactoryLike.PairVariant.MISSING_ENUMERABLE_ERC20) {
            offer.asset = address(lssvmPair.token());
        } else {
            offer.asset = ETH_ADDRESS;
        }

        uint256 considerationAmount;
        ( , , , considerationAmount, ) = lssvmPair.getBuyNFTQuote(1);
        offer.amount = uint128(considerationAmount / 2);
        offer.expiration = uint32(block.timestamp + 1);

        (, LoanAuction memory loanAuction) = createOfferAndTryPurchaseWithFinancing(
            offer,
            lssvmPair,
            nftId,
            "should work"
        );

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
    }

    function test_fuzz_PurchaseWithSudoswap_simplest_case_ETH(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        (ILSSVMPair lssvmPair, uint256 nftId) = createAndValidateLssvmPairWithETH();

        _test_purchaseWithFinancing_simplest_case(offer, lssvmPair, nftId);
    }

    function test_unit_PurchaseWithFinancingSudoswap_simplest_case_ETH() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (ILSSVMPair lssvmPair, uint256 nftId) = createAndValidateLssvmPairWithETH();

        _test_purchaseWithFinancing_simplest_case(offer, lssvmPair, nftId);
    }

    function test_fuzz_PurchaseWithFinancing_simplest_case_DAI(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
    (ILSSVMPair lssvmPair, uint256 nftId) = createAndValidateLssvmPairWithDAI();

    _test_purchaseWithFinancing_simplest_case(offer, lssvmPair, nftId);
    }

    function test_unit_PurchaseWithFinancing_simplest_case_DAI() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (ILSSVMPair lssvmPair, uint256 nftId) = createAndValidateLssvmPairWithDAI();

        _test_purchaseWithFinancing_simplest_case(offer, lssvmPair, nftId);
    }

    //
    // HELPERS
    //
    function createOfferAndTryPurchaseWithFinancing(
        Offer memory offer,
        ILSSVMPair lssvmPair,
        uint256 nftId,
        bytes memory errorCode
    ) internal returns (Offer memory, LoanAuction memory) {
        Offer memory offerCreated = createOffer(offer, lender1);

        LoanAuction memory loan = tryPurchaseWithFinancing(offer, lssvmPair, nftId, errorCode);
        return (offerCreated, loan);
    }

    function tryPurchaseWithFinancing(
        Offer memory offer,
        ILSSVMPair lssvmPair,
        uint256 nftId,
        bytes memory errorCode
    ) internal returns (LoanAuction memory) {
        vm.startPrank(borrower1);
        bytes32 offerHash = offers.getOfferHash(offer);

        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }
        uint256 borrowerPays = (uint256(offer.amount) * 2) - uint256(offer.amount);

        if (offer.asset == ETH_ADDRESS) {
            sudoswapPWF.purchaseWithFinancingSudoswap{ value: borrowerPays }(
                offerHash,
                offer.floorTerm,
                lssvmPair,
                nftId
            );
        } else {
            daiToken.approve(address(sudoswapPWF), borrowerPays);
            sudoswapPWF.purchaseWithFinancingSudoswap(
                offerHash,
                offer.floorTerm,
                lssvmPair,
                nftId
            );
        }
        vm.stopPrank();

        return lending.getLoanAuction(offer.nftContractAddress, nftId);
    }

    function createAndValidateLssvmPairWithETH() public returns (ILSSVMPair, uint256) {
        (ILSSVMPair lssvmPair, uint256 nftId) = ethPudgyLssvmPair();
        // validate that pool holds the nft with the given Id
        assertEq(ERC721Mock(address(lssvmPair.nft())).ownerOf(nftId), address(lssvmPair));

        return (lssvmPair, nftId);
    }

    function createAndValidateLssvmPairWithDAI() public returns (ILSSVMPair, uint256) {
        (ILSSVMPair lssvmPair, uint256 nftId) = daiPudgyLssvmPair();
        // validate that pool holds the nft with the given Id
        assertEq(ERC721Mock(address(lssvmPair.nft())).ownerOf(nftId), address(lssvmPair));
        return (lssvmPair, nftId);
    }

    function ethPudgyLssvmPair() internal pure returns (ILSSVMPair, uint256) {
        ILSSVMPair lssvmPair = ILSSVMPair(0x451018623F2EA29A625Ac5e051720eEAc2b0E765); // ETH-PUDGY_PENGUIN pair pool on Sudoswap
        uint256 nftId = 3338;
        return (lssvmPair, nftId);
    }

    function daiPudgyLssvmPair() internal returns (ILSSVMPair, uint256) {
        address _PUDGY_PENGUIN_CONTRACT_ADDRESS = 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8;
        address _PUDGY1_OWNER = 0x2cbC202392C0F0C846Bf028777a5e9B4e49D9FaC;
        vm.prank(borrower1);
        daiToken.transfer(_PUDGY1_OWNER, 1);

        vm.startPrank(_PUDGY1_OWNER);
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;
        ILSSVMPairFactoryLike.CreateERC20PairParams memory params =  ILSSVMPairFactoryLike.CreateERC20PairParams(
            address(daiToken),
            _PUDGY_PENGUIN_CONTRACT_ADDRESS,
            0x432f962D8209781da23fB37b6B59ee15dE7d9841,
            payable(address(0)),
            ILSSVMPairFactoryLike.PoolType.TRADE,
            2 ether,
            1,
            uint128(10 gwei),
            nftIds,
            1
        );
        daiToken.approve(SUDOSWAP_FACTORY_ADDRESS, params.initialTokenBalance);
        ERC721Mock(_PUDGY_PENGUIN_CONTRACT_ADDRESS).approve(SUDOSWAP_FACTORY_ADDRESS, nftIds[0]);
        ILSSVMPair lssvmPair = ILSSVMPairFactoryLike(SUDOSWAP_FACTORY_ADDRESS).createPairERC20(params);
        vm.stopPrank();
        return (lssvmPair, 1);
    }
}
