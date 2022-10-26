pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../../interfaces/niftyapes/offers/IOffersStructs.sol";

contract TestSudoswapFlashPurchaseIntegration is Test, OffersLoansRefinancesFixtures, ERC721HolderUpgradeable {
    function setUp() public override {
        // pin block to time of writing test to reflect consistent state
        vm.rollFork(15727117);

        super.setUp();
    }

    function _test_flashPurchaseSudoswap_simplest_case(
        Offer memory offer,
        ILSSVMPair lssvmPair,
        uint256[] memory nftIds,
        bool withSignature
    ) private {
        address nftContractAddress = address(lssvmPair.nft());
        offer.nftContractAddress = nftContractAddress;
        offer.nftId = nftIds[0];

        ILSSVMPairFactoryLike.PairVariant pairVariant = lssvmPair.pairVariant();
        if (pairVariant == ILSSVMPairFactoryLike.PairVariant.ENUMERABLE_ERC20 || pairVariant == ILSSVMPairFactoryLike.PairVariant.MISSING_ENUMERABLE_ERC20) {
            offer.asset = address(lssvmPair.token());
        } else {
            offer.asset = ETH_ADDRESS;
        }

        ( , , , uint256 totalConsiderationAmount, ) = lssvmPair.getBuyNFTQuote(nftIds.length);
        offer.amount = uint128(totalConsiderationAmount / (nftIds.length * 2));
        offer.expiration = uint32(block.timestamp + 1);
        if (nftIds.length > 1) {
            offer.floorTerm = true;
            offer.floorTermLimit = 2;
        }

        if (!withSignature) {
            createOfferAndTryFlashPurchase(
                offer,
                lssvmPair,
                nftIds,
                "should work"
            );
        } else {
            signOfferAndTryFlashPurchaseSignature(
                offer,
                lssvmPair,
                nftIds,
                "should work"
            );
        }

        for (uint256 i; i < nftIds.length; i++) {
            LoanAuction memory loanAuction = lending.getLoanAuction(offer.nftContractAddress, nftIds[i]);
            // lending contract has NFT
            assertEq(
                IERC721Upgradeable(offer.nftContractAddress).ownerOf(nftIds[i]),
                address(lending)
            );
            // loan auction exists
            assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
            // loan auction exists
            assertEq(loanAuction.nftOwner, borrower1);
            assertEq(loanAuction.amountDrawn, offer.amount);
        }
        
    }

    function test_fuzz_FlashPurchaseSudoswap_simplest_case_ETH(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithETH(1);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, false);
    }

    function test_unit_FlashPurchaseSudoswap_simplest_case_ETH() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithETH(1);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, false);
    }

    function test_fuzz_FlashPurchaseSudoswap_simplest_case_DAI(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
    (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithDAI(1);

    _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, false);
    }

    function test_unit_FlashPurchaseSudoswap_simplest_case_DAI() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithDAI(1);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, false);
    }

    function test_fuzz_FlashPurchaseSudoswapSignature_simplest_case_ETH(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithETH(1);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, true);
    }

    function test_unit_FlashPurchaseSudoswapSignature_simplest_case_ETH() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithETH(1);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, true);
    }

    function test_fuzz_FlashPurchaseSudoswapSignature_simplest_case_DAI(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
    (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithDAI(1);

    _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, true);
    }

    function test_unit_FlashPurchaseSudoswapSignature_simplest_case_DAI() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithDAI(1);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, true);
    }

    function test_fuzz_FlashPurchaseSudoswap_TwoNFTs_ETH(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithETH(2);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, false);
    }

    function test_unit_FlashPurchaseSudoswap_TwoNFTs_ETH() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithETH(2);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, false);
    }

    function test_fuzz_FlashPurchaseSudoswap_TwoNFTs_DAI(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
    (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithDAI(2);

    _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, false);
    }

    function test_unit_FlashPurchaseSudoswap_TwoNFTs_DAI() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithDAI(2);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, false);
    }

    function test_fuzz_FlashPurchaseSudoswapSignature_TwoNFTs_ETH(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithETH(2);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, true);
    }

    function test_unit_FlashPurchaseSudoswapSignature_TwoNFTs_ETH() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithETH(2);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, true);
    }

    function test_fuzz_FlashPurchaseSudoswapSignature_TwoNFTs_DAI(
        FuzzedOfferFields memory fuzzedOfferData
    ) public validateFuzzedOfferFields(fuzzedOfferData) {
        Offer memory offer = offerStructFromFields(fuzzedOfferData, defaultFixedOfferFields);
    (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithDAI(2);

    _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, true);
    }

    function test_unit_FlashPurchaseSudoswapSignature_TwoNFTs_DAI() public {
        Offer memory offer = offerStructFromFields(
            defaultFixedFuzzedFieldsForFastUnitTesting,
            defaultFixedOfferFields
        );
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = createAndValidateLssvmPairWithDAI(2);

        _test_flashPurchaseSudoswap_simplest_case(offer, lssvmPair, nftIds, true);
    }


    //
    // HELPERS
    //
    function createOfferAndTryFlashPurchase(
        Offer memory offer,
        ILSSVMPair lssvmPair,
        uint256[] memory nftIds,
        bytes memory errorCode
    ) internal {
        createOffer(offer, lender1);
        tryFlashPurchase(offer, lssvmPair, nftIds, errorCode);
    }

    function signOfferAndTryFlashPurchaseSignature(
        Offer memory offer,
        ILSSVMPair lssvmPair,
        uint256[] memory nftIds,
        bytes memory errorCode
    ) internal {
        bytes memory signature = signOffer(lender1_private_key, offer);
        tryFlashPurchaseSignature(offer, signature, lssvmPair, nftIds, errorCode);
    }

    function tryFlashPurchase(
        Offer memory offer,
        ILSSVMPair lssvmPair,
        uint256[] memory nftIds,
        bytes memory errorCode
    ) internal {
        bytes32 offerHash = offers.getOfferHash(offer);

        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }
        ( , , , uint256 totalConsiderationAmount, ) = lssvmPair.getBuyNFTQuote(nftIds.length);
        uint256 borrowerPays = totalConsiderationAmount - (uint256(offer.amount) * nftIds.length );

        if (offer.asset == ETH_ADDRESS) {
            vm.startPrank(borrower1);
            sudoswapFlashPurchase.flashPurchaseSudoswap{ value: borrowerPays }(
                offerHash,
                offer.floorTerm,
                lssvmPair,
                nftIds
            );
            vm.stopPrank();
        } else {
            mintDai(borrower1, borrowerPays);
            vm.startPrank(borrower1);
            daiToken.approve(address(sudoswapFlashPurchase), borrowerPays);
            sudoswapFlashPurchase.flashPurchaseSudoswap(
                offerHash,
                offer.floorTerm,
                lssvmPair,
                nftIds
            );
            vm.stopPrank();
        }
    }

    function tryFlashPurchaseSignature(
        Offer memory offer,
        bytes memory signature,
        ILSSVMPair lssvmPair,
        uint256[] memory nftIds,
        bytes memory errorCode
    ) internal {
        if (bytes16(errorCode) != bytes16("should work")) {
            vm.expectRevert(errorCode);
        }
        ( , , , uint256 totalConsiderationAmount, ) = lssvmPair.getBuyNFTQuote(nftIds.length);
        uint256 borrowerPays =  totalConsiderationAmount - (uint256(offer.amount) * nftIds.length );

        if (offer.asset == ETH_ADDRESS) {
            vm.startPrank(borrower1);
            sudoswapFlashPurchase.flashPurchaseSudoswapSignature{ value: borrowerPays }(
                offer,
                signature,
                lssvmPair,
                nftIds
            );
            vm.stopPrank();
        } else {
            mintDai(borrower1, borrowerPays);
            vm.startPrank(borrower1);
            daiToken.approve(address(sudoswapFlashPurchase), borrowerPays);
            sudoswapFlashPurchase.flashPurchaseSudoswapSignature(
                offer,
                signature,
                lssvmPair,
                nftIds
            );
            vm.stopPrank();
        }
    }

    function createAndValidateLssvmPairWithETH(uint256 numOfNfts) public returns (ILSSVMPair, uint256[] memory) {
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = ethPudgyLssvmPair(numOfNfts);
        // validate that pool holds the nft with the given Id
        for (uint256 i = 0; i < nftIds.length; ++i) {
            assertEq(ERC721Mock(address(lssvmPair.nft())).ownerOf(nftIds[i]), address(lssvmPair));
        }
        return (lssvmPair, nftIds);
    }

    function createAndValidateLssvmPairWithDAI(uint256 numOfNfts) public returns (ILSSVMPair, uint256[] memory) {
        (ILSSVMPair lssvmPair, uint256[] memory nftIds) = daiPudgyLssvmPair(numOfNfts);
        // validate that pool holds the nfts with the given Ids
        for (uint256 i = 0; i < nftIds.length; ++i) {
            assertEq(ERC721Mock(address(lssvmPair.nft())).ownerOf(nftIds[i]), address(lssvmPair));
        }
        
        return (lssvmPair, nftIds);
    }

    function ethPudgyLssvmPair(uint256 numOfNfts) internal pure returns (ILSSVMPair, uint256[] memory) {
        ILSSVMPair lssvmPair = ILSSVMPair(0x451018623F2EA29A625Ac5e051720eEAc2b0E765); // ETH-PUDGY_PENGUIN pair pool on Sudoswap
        uint256[] memory nftIds;
        if (numOfNfts > 1) {
            nftIds = new uint256[](2);
            nftIds[0] = 3338;
            nftIds[1] = 3794;
        } else {
            nftIds = new uint256[](1);
            nftIds[0] = 3338;
        }
        
        return (lssvmPair, nftIds);
    }

    function daiPudgyLssvmPair(uint256 numOfNfts) internal returns (ILSSVMPair, uint256[] memory) {
        address _PUDGY_PENGUIN_CONTRACT_ADDRESS = 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8;
        address _PUDGY1_OWNER = 0x451018623F2EA29A625Ac5e051720eEAc2b0E765;
        mintDai(_PUDGY1_OWNER, 2);
        vm.startPrank(_PUDGY1_OWNER);
        uint256[] memory nftIds;
        if (numOfNfts > 1) {
            nftIds = new uint256[](2);
            nftIds[0] = 3338;
            nftIds[1] = 3794;
            ERC721Mock(_PUDGY_PENGUIN_CONTRACT_ADDRESS).approve(SUDOSWAP_FACTORY_ADDRESS, nftIds[0]);
            ERC721Mock(_PUDGY_PENGUIN_CONTRACT_ADDRESS).approve(SUDOSWAP_FACTORY_ADDRESS, nftIds[1]);
        } else {
            nftIds = new uint256[](1);
            nftIds[0] = 3338;
            ERC721Mock(_PUDGY_PENGUIN_CONTRACT_ADDRESS).approve(SUDOSWAP_FACTORY_ADDRESS, nftIds[0]);
        }

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
            2
        );
        daiToken.approve(SUDOSWAP_FACTORY_ADDRESS, params.initialTokenBalance);
        
        ILSSVMPair lssvmPair = ILSSVMPairFactoryLike(SUDOSWAP_FACTORY_ADDRESS).createPairERC20(params);
        vm.stopPrank();
        return (lssvmPair, nftIds);
    }
}