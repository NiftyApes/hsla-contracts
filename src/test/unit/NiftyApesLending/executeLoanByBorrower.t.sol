// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../common/BaseTest.sol";

import "../../mock/CERC20Mock.sol";
import "../../mock/ERC20Mock.sol";
import "../../mock/ERC721Mock.sol";

import "../../../Lending.sol";
import "../../../Liquidity.sol";
import "../../../Offers.sol";

contract TestExecuteLoanByBorrower is Test, BaseTest, ILendingStructs, IOffersStructs {
    NiftyApesLending private lendingContract;
    NiftyApesLiquidity private liquidityContract;
    NiftyApesOffers private offersContract;

    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    ERC721Mock mockNft;

    // Below are two random addresses
    address private constant LENDER = 0x503408564C50b43208529faEf9bdf9794c015d52;
    address private constant BORROWER = 0x4a3A70D6Be2290f5F57Ac7E64b9A1B7695f5b0B3;

    function setUp() public {
        lendingContract = new NiftyApesLending();
        lendingContract.initialize();

        liquidityContract = new NiftyApesLiquidity();
        liquidityContract.initialize();

        offersContract = new NiftyApesOffers();
        offersContract.initialize();

        // _burnCErc20 checks to see whether caller is Lending
        liquidityContract.updateLendingContractAddress(address(lendingContract));
        lendingContract.updateLiquidityContractAddress(address(liquidityContract));
        // createOffer calls Liquidity when getCAsset
        offersContract.updateLiquidityContractAddress(address(liquidityContract));
        // if offer floor term = false, then lending tries to remove offer
        // after borrower execute, and Offer looks to make sure Lending is caller
        offersContract.updateLendingContractAddress(address(lendingContract));
        lendingContract.updateOffersContractAddress(address(offersContract));

        usdcToken = new ERC20Mock();
        usdcToken.initialize("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock();
        cUSDCToken.initialize(usdcToken);

        liquidityContract.setCAssetAddress(address(usdcToken), address(cUSDCToken));
        liquidityContract.setMaxCAssetBalance(address(usdcToken), 2**256 - 1);

        mockNft = new ERC721Mock();
        mockNft.initialize("BoredApe", "BAYC");
    }

    function mint(
        address to,
        address nftContractAddress,
        uint256 nftId
    ) public {
        ERC721Mock(nftContractAddress).safeMint(address(to), nftId);
    }

    function fundAndSupplyErc20(
        address to,
        address erc20Address,
        uint256 amount
    ) public {
        usdcToken.mint(address(to), amount);

        vm.startPrank(to);
        usdcToken.approve(address(liquidityContract), amount);
        liquidityContract.supplyErc20(erc20Address, amount);
        vm.stopPrank();
    }

    function testExecuteLoanByBorrower_works(
        bool fixedTerms,
        bool floorTerm,
        uint96 interestRatePerSecond,
        uint128 amount,
        uint32 duration,
        uint32 expiration
    ) public {
        vm.assume(amount > 0);
        vm.assume(duration > 1 days);
        // to avoid overflow when loanAuction.loanEndTimestamp = _currentTimestamp32() + offer.duration;
        vm.assume(duration <= 2**32 - 1 - block.timestamp);
        vm.assume(expiration > block.timestamp);

        address asset = address(usdcToken);
        address nftContractAddress = address(mockNft);
        uint256 nftId = 1;

        fundAndSupplyErc20(LENDER, asset, amount);
        mint(BORROWER, nftContractAddress, nftId);

        Offer memory offerToCreate = Offer({
            creator: LENDER,
            lenderOffer: true,
            nftId: nftId,
            nftContractAddress: nftContractAddress,
            asset: asset,
            fixedTerms: fixedTerms,
            floorTerm: floorTerm,
            interestRatePerSecond: interestRatePerSecond,
            amount: amount,
            duration: duration,
            expiration: expiration
        });

        vm.startPrank(LENDER);
        offersContract.createOffer(offerToCreate);
        vm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offerToCreate);

        vm.startPrank(BORROWER);
        ERC721Mock(nftContractAddress).approve(address(lendingContract), nftId);
        lendingContract.executeLoanByBorrower(nftContractAddress, nftId, offerHash, floorTerm);
        vm.stopPrank();

        assertEq(usdcToken.balanceOf(BORROWER), amount);
    }

    function testCannotExecuteLoanByBorrower_if_offer_expired(
        bool fixedTerms,
        bool floorTerm,
        uint96 interestRatePerSecond,
        uint128 amount,
        uint32 duration,
        uint32 expiration
    ) public {
        vm.assume(amount > 0);
        vm.assume(duration > 1 days);
        // to avoid overflow when loanAuction.loanEndTimestamp = _currentTimestamp32() + offer.duration;
        vm.assume(duration <= 2**32 - 1 - block.timestamp);
        // we want it not expired now so that we can create offer
        // will cause it to be expired later with vm.warp
        vm.assume(expiration > block.timestamp);

        address asset = address(usdcToken);
        address nftContractAddress = address(mockNft);
        uint256 nftId = 1;

        fundAndSupplyErc20(LENDER, asset, amount);
        mint(BORROWER, nftContractAddress, nftId);

        Offer memory offerToCreate = Offer({
            creator: LENDER,
            lenderOffer: true,
            nftId: nftId,
            nftContractAddress: nftContractAddress,
            asset: asset,
            fixedTerms: fixedTerms,
            floorTerm: floorTerm,
            interestRatePerSecond: interestRatePerSecond,
            amount: amount,
            duration: duration,
            expiration: expiration
        });

        vm.startPrank(LENDER);
        offersContract.createOffer(offerToCreate);
        vm.stopPrank();

        vm.warp(expiration);

        bytes32 offerHash = offersContract.getOfferHash(offerToCreate);

        vm.startPrank(BORROWER);
        ERC721Mock(nftContractAddress).approve(address(lendingContract), nftId);
        vm.expectRevert("00010");
        lendingContract.executeLoanByBorrower(nftContractAddress, nftId, offerHash, floorTerm);
        vm.stopPrank();
    }
}
