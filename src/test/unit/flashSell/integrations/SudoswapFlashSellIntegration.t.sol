// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "../../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../../interfaces/niftyapes/lending/ILendingStructs.sol";

contract TestSudoswapFlashSellIntegration is Test, ILendingStructs, OffersLoansRefinancesFixtures {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    function setUp() public override {
        super.setUp();
    }

    function _test_unit_flashSellSudoswap_simplest_case(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanBefore = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        // skip time to accrue interest
        skip(uint256(loanBefore.loanEndTimestamp - loanBefore.loanBeginTimestamp) / 2);

        uint256 minValueRequiredToCloseTheLoan = _calculateTotalLoanPaymentAmountAtTimestamp(loanBefore, block.timestamp);
        uint256 minProfitForTheBorrower = 1 ether; // assume any profit the borrower wants
        uint256 salePrice = minValueRequiredToCloseTheLoan + minProfitForTheBorrower;
        ILSSVMPair lssvmPair;
        if (loanBefore.asset == ETH_ADDRESS) {
            lssvmPair = ethLssvmPair(salePrice);
        } else {
            lssvmPair = daiLssvmPair(salePrice);
        }

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
            address(sudoswapFlashSellIntegration),
            bytes(abi.encode(lssvmPair))
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
        assertEq(address(lssvmPair), nftOwnerAfter);
        assertGt(borrower1AssetBalanceAfter - borrower1AssetBalanceBefore, minProfitForTheBorrower);
        assertEq(loanAfter.loanBeginTimestamp, 0);
    }

    function test_unit_flashSellSudoswap_simplest_case_ETH() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_flashSellSudoswap_simplest_case(fixedForSpeed);
    }

    function test_fuzz_flashSellSudoswap_simplest_case_ETH(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        fuzzedOfferData.randomAsset = 1;
        _test_unit_flashSellSudoswap_simplest_case(fuzzedOfferData);
    }

    function test_unit_flashSellSudoswap_simplest_case_DAI() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 0;
        _test_unit_flashSellSudoswap_simplest_case(fixedForSpeed);
    }

    function test_fuzz_flashSellSudoswap_simplest_case_DAI(FuzzedOfferFields memory fuzzedOfferData) public validateFuzzedOfferFields(fuzzedOfferData) {
        fuzzedOfferData.randomAsset = 0;
        _test_unit_flashSellSudoswap_simplest_case(fuzzedOfferData);
    }

    function _test_unit_cannot_flashSellSudoswap_InsufficientSaleValue(FuzzedOfferFields memory fuzzed) private {
        Offer memory offer = offerStructFromFields(fuzzed, defaultFixedOfferFields);
        createOfferAndTryToExecuteLoanByBorrower(offer, "should work");

        LoanAuction memory loanBefore = lending.getLoanAuction(offer.nftContractAddress, offer.nftId);
        
        uint256 minValueRequiredToCloseTheLoan = _calculateTotalLoanPaymentAmountAtTimestamp(loanBefore, block.timestamp);
       
        uint256 salePrice = minValueRequiredToCloseTheLoan * 9 / 10;
        ILSSVMPair lssvmPair;
        if (loanBefore.asset == ETH_ADDRESS) {
            lssvmPair = ethLssvmPair(salePrice);
        } else {
            lssvmPair = daiLssvmPair(salePrice);
        }

        vm.startPrank(borrower1);
        vm.expectRevert("outputAmount too low");

        flashSell.borrowNFTForSale(
            offer.nftContractAddress,
            offer.nftId,
            address(sudoswapFlashSellIntegration),
            bytes(abi.encode(lssvmPair))
        );
        vm.stopPrank();
    }

    function test_unit_cannot_flashSellSudoswap_InsufficientSaleValue() public {
        FuzzedOfferFields memory fixedForSpeed = defaultFixedFuzzedFieldsForFastUnitTesting;
        fixedForSpeed.randomAsset = 1;
        _test_unit_cannot_flashSellSudoswap_InsufficientSaleValue(fixedForSpeed);
    }

    function daiLssvmPair(uint256 minSalePrice) internal returns (ILSSVMPair) {
        uint256 salePricePlusProtocolFee =  minSalePrice * 101 / 100;
        
        mockNft.safeMint(users[0], 4);
        mintDai(users[0], salePricePlusProtocolFee * 2);

        uint256[] memory nftIds;
        nftIds = new uint256[](1);
        nftIds[0] = 4;
        vm.startPrank(users[0]);
        mockNft.approve(SUDOSWAP_FACTORY_ADDRESS, nftIds[0]);

        
        
        ILSSVMPairFactoryLike.CreateERC20PairParams memory params =  ILSSVMPairFactoryLike.CreateERC20PairParams(
            address(daiToken),
            address(mockNft),
            0x5B6aC51d9B1CeDE0068a1B26533CAce807f883Ee,
            payable(address(0)),
            ILSSVMPairFactoryLike.PoolType.TOKEN,
            uint128(0),
            0,
            uint128(salePricePlusProtocolFee),
            nftIds,
            salePricePlusProtocolFee
        );
        daiToken.approve(SUDOSWAP_FACTORY_ADDRESS, params.initialTokenBalance);
        
        ILSSVMPair lssvmPair = ILSSVMPairFactoryLike(SUDOSWAP_FACTORY_ADDRESS).createPairERC20(params);
        vm.stopPrank();
        return lssvmPair;
    }

    function ethLssvmPair(uint256 minSalePrice) internal returns (ILSSVMPair) {
        uint256 salePricePlusProtocolFee =  minSalePrice * 101 / 100;
        mockNft.safeMint(users[0], 4);

        uint256[] memory nftIds;
        nftIds = new uint256[](1);
        nftIds[0] = 4;
        vm.startPrank(users[0]);
        mockNft.approve(SUDOSWAP_FACTORY_ADDRESS, nftIds[0]);
        
        ILSSVMPair lssvmPair = ILSSVMPairFactoryLike(SUDOSWAP_FACTORY_ADDRESS).createPairETH{value: salePricePlusProtocolFee}(
            address(mockNft),
            0x5B6aC51d9B1CeDE0068a1B26533CAce807f883Ee,
            payable(address(0)),
            ILSSVMPairFactoryLike.PoolType.TOKEN,
            uint128(0),
            0,
            uint128(salePricePlusProtocolFee),
            nftIds
        );
        vm.stopPrank();
        return lssvmPair;
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
}