// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../interfaces/compound/ICERC20.sol";
import "../../interfaces/compound/ICEther.sol";
import "../../Lending.sol";
import "../../Liquidity.sol";
import "../../Offers.sol";
import "../../interfaces/niftyapes/lending/ILendingEvents.sol";
import "../../interfaces/niftyapes/offers/IOffersEvents.sol";

import "../common/BaseTest.sol";
import "../mock/CERC20Mock.sol";
import "../mock/CEtherMock.sol";
import "../mock/ERC20Mock.sol";
import "../mock/ERC721Mock.sol";

import "../Console.sol";

contract LendingAuctionUnitTest is
    BaseTest,
    ILendingEvents,
    ILendingStructs,
    IOffersEvents,
    IOffersStructs,
    ERC721HolderUpgradeable
{
    NiftyApesLending lendingAuction;
    NiftyApesOffers offersContract;
    NiftyApesLiquidity liquidityProviders;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    CEtherMock cEtherToken;

    ERC721Mock mockNft;

    bool acceptEth;

    address constant ZERO_ADDRESS = address(0);
    address constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address constant LENDER_1 = address(0x1010);
    address constant LENDER_2 = address(0x2020);
    address constant LENDER_3 = address(0x3030);
    address constant BORROWER_1 = address(0x101);
    address constant OWNER = address(0xFFFFFFFFFFFFFF);

    uint256 immutable SIGNER_PRIVATE_KEY_1 =
        0x60b919c82f0b4791a5b7c6a7275970ace1748759ebdaa4076d7eeed9dbcff3c3;
    address immutable SIGNER_1 = 0x503408564C50b43208529faEf9bdf9794c015d52;
    address immutable SIGNER_2 = 0x4a3A70D6Be2290f5F57Ac7E64b9A1B7695f5b0B3;

    address constant SANCTIONED_ADDRESS = 0x7FF9cFad3877F21d41Da833E2F775dB0569eE3D9;

    receive() external payable {
        require(acceptEth, "acceptEth");
    }

    function setUp() public {
        lendingAuction = new NiftyApesLending();
        lendingAuction.initialize();

        liquidityProviders = new NiftyApesLiquidity();
        liquidityProviders.initialize();

        offersContract = new NiftyApesOffers();
        offersContract.initialize();

        lendingAuction.updateOffersContractAddress(address(offersContract));
        lendingAuction.updateLiquidityContractAddress(address(liquidityProviders));

        liquidityProviders.updateLendingContractAddress(address(lendingAuction));

        offersContract.updateLendingContractAddress(address(lendingAuction));
        offersContract.updateLiquidityContractAddress(address(liquidityProviders));

        usdcToken = new ERC20Mock();
        usdcToken.initialize("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock();
        cUSDCToken.initialize(usdcToken);
        liquidityProviders.setCAssetAddress(address(usdcToken), address(cUSDCToken));
        liquidityProviders.setMaxCAssetBalance(address(usdcToken), 2**256 - 1);

        cEtherToken = new CEtherMock();
        cEtherToken.initialize();
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.setMaxCAssetBalance(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            2**256 - 1
        );

        acceptEth = true;

        mockNft = new ERC721Mock();
        mockNft.initialize("BoredApe", "BAYC");

        mockNft.safeMint(address(this), 1);
        mockNft.approve(address(lendingAuction), 1);

        mockNft.safeMint(address(this), 2);
        mockNft.approve(address(lendingAuction), 2);

        lendingAuction.transferOwnership(OWNER);
    }

    function signOffer(uint256 signerPrivateKey, Offer memory offer) public returns (bytes memory) {
        // This is the EIP712 signed hash
        bytes32 offerHash = offersContract.getOfferHash(offer);

        return sign(signerPrivateKey, offerHash);
    }

    function setupLoan() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444444,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    // LENDER_1 makes an offer on mockNft #1, owned by address(this)
    // address(this) executes loan
    // LENDER_2 makes a better offer with a greater amount offered
    // LENDER_2 initiates refinance
    // Useful for testing drawLoanAmount functionality
    // which requires a lender-initiated refinance for a greater amount
    function setupRefinance() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444444,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 7 ether);
        usdcToken.approve(address(liquidityProviders), 7 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 7 ether);

        hevm.warp(block.timestamp + 12 hours);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444444,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);

        hevm.stopPrank();
    }

    function testGetOffer_returns_empty_offer() public {
        Offer memory offer = offersContract.getOffer(
            address(0x0000000000000000000000000000000000000001),
            2,
            "",
            false
        );

        assertEq(offer.creator, ZERO_ADDRESS);
        assertEq(offer.nftContractAddress, ZERO_ADDRESS);
        assertEq(offer.interestRatePerSecond, 0);
        assertTrue(!offer.fixedTerms);
        assertTrue(!offer.floorTerm);
        assertEq(offer.nftId, 0);
        assertEq(offer.asset, ZERO_ADDRESS);
        assertEq(offer.amount, 0);
        assertEq(offer.duration, 0);
        assertEq(offer.expiration, 0);
    }

    // createOffer Tests

    function testCannotCreateOffer_asset_not_whitelisted() public {
        Offer memory offer = Offer({
            creator: address(0x0000000000000000000000000000000000000001),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 4,
            asset: address(0x0000000000000000000000000000000000000005),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        hevm.expectRevert("asset allow list");

        offersContract.createOffer(offer);
    }

    function testCannotCreateOffer_offer_does_not_match_sender() public {
        Offer memory offer = Offer({
            creator: address(0x0000000000000000000000000000000000000001),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.expectRevert("is not offer creator");

        offersContract.createOffer(offer);
    }

    function testCannotCreateOffer_not_enough_balance() public {
        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.expectRevert("insufficient cToken balance");

        offersContract.createOffer(offer);
    }

    function testCreateOffer_works() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        Offer memory actual = offersContract.getOffer(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(actual.creator, address(this));
        assertEq(actual.nftContractAddress, address(0x0000000000000000000000000000000000000002));
        assertEq(actual.interestRatePerSecond, 3);
        assertTrue(actual.fixedTerms);
        assertTrue(actual.floorTerm);
        assertTrue(actual.lenderOffer);
        assertEq(actual.nftId, 4);
        assertEq(actual.asset, address(usdcToken));
        assertEq(actual.amount, 6);
        assertEq(actual.duration, 7);
        assertEq(actual.expiration, uint32(block.timestamp + 1));
    }

    function testCreateOffer_works_event() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectEmit(true, false, false, true);

        emit NewOffer(
            address(this),
            address(usdcToken),
            address(0x0000000000000000000000000000000000000002),
            4,
            offer,
            offerHash
        );

        offersContract.createOffer(offer);
    }

    // removeOffer Tests

    function testCannotRemoveOffer_other_user() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.prank(address(0x0000000000000000000000000000000000000001));

        hevm.expectRevert("is not offer creator");

        offersContract.removeOffer(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testRemoveOffer_works() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        offersContract.removeOffer(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        Offer memory actual = offersContract.getOffer(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(actual.creator, ZERO_ADDRESS);
        assertEq(actual.nftContractAddress, ZERO_ADDRESS);
        assertEq(actual.interestRatePerSecond, 0);
        assertTrue(!actual.fixedTerms);
        assertTrue(!actual.floorTerm);
        assertEq(actual.nftId, 0);
        assertEq(actual.asset, ZERO_ADDRESS);
        assertEq(actual.amount, 0);
        assertEq(actual.duration, 0);
        assertEq(actual.expiration, 0);
    }

    function testRemoveOffer_event() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectEmit(true, false, false, true);

        emit OfferRemoved(
            address(this),
            address(usdcToken),
            address(0x0000000000000000000000000000000000000002),
            4,
            offer,
            offerHash
        );

        offersContract.removeOffer(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    // executeLoanByBorrower Tests

    function testCannotExecuteLoanByBorrower_asset_not_in_allow_list() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        liquidityProviders.setCAssetAddress(
            address(usdcToken),
            address(0x0000000000000000000000000000000000000000)
        );

        hevm.expectRevert("asset allow list");

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_no_offer_present() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("lender offer");

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_offer_expired() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 30 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.warp(block.timestamp + 1 days);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("offer has expired");

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_offer_duration() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("offer duration");

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_not_owning_nft() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        mockNft.transferFrom(address(this), address(0x0000000000000000000000000000000000000001), 1);

        hevm.expectRevert("nft owner");

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_not_enough_tokens() public {
        hevm.startPrank(LENDER_2);
        usdcToken.mint(LENDER_2, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);
        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer1 = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer1);

        bytes32 offerHash1 = offersContract.getOfferHash(offer1);

        Offer memory offer2 = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        hevm.stopPrank();

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        // funds for first loan are available
        lendingAuction.executeLoanByBorrower(
            offer1.nftContractAddress,
            offer1.nftId,
            offerHash1,
            offer1.floorTerm
        );

        hevm.expectRevert("Insufficient cToken balance");

        lendingAuction.executeLoanByBorrower(
            offer2.nftContractAddress,
            offer2.nftId,
            offerHash2,
            offer2.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_underlying_transfer_fails() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        usdcToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_eth_payment_fails() public {
        hevm.startPrank(LENDER_1);

        liquidityProviders.supplyEth{ value: 6 }();

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        acceptEth = false;

        hevm.expectRevert("Address: unable to send value, recipient may have reverted");

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_borrower_offer() public {
        hevm.startPrank(LENDER_1);

        liquidityProviders.supplyEth{ value: 6 }();

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        mockNft.transferFrom(address(this), LENDER_1, 1);

        hevm.startPrank(LENDER_1);
        mockNft.approve(address(lendingAuction), 1);

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("lender offer");

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testExecuteLoanByBorrower_works_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 3);
        assertTrue(loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 1 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);

        // ensure that the offer is still there since its a floor offer

        Offer memory onChainOffer = offersContract.getOffer(address(mockNft), 1, offerHash, true);

        assertEq(onChainOffer.creator, LENDER_1);
        assertEq(onChainOffer.nftContractAddress, address(mockNft));
        assertEq(onChainOffer.interestRatePerSecond, 3);
        assertTrue(onChainOffer.fixedTerms);
        assertTrue(onChainOffer.floorTerm);
        assertTrue(onChainOffer.lenderOffer);
        assertEq(onChainOffer.nftId, 1);
        assertEq(onChainOffer.asset, address(usdcToken));
        assertEq(onChainOffer.amount, 6);
        assertEq(onChainOffer.duration, 1 days);
        assertEq(onChainOffer.expiration, uint32(block.timestamp + 1));
    }

    function testExecuteLoanByBorrower_works_not_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 3);
        assertTrue(loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 1 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);

        // ensure that the offer is gone
        Offer memory onChainOffer = offersContract.getOffer(address(mockNft), 1, offerHash, false);

        assertEq(onChainOffer.creator, ZERO_ADDRESS);
        assertEq(onChainOffer.nftContractAddress, ZERO_ADDRESS);
        assertEq(onChainOffer.interestRatePerSecond, 0);
        assertTrue(!onChainOffer.fixedTerms);
        assertTrue(!onChainOffer.floorTerm);
        assertTrue(!onChainOffer.lenderOffer);
        assertEq(onChainOffer.nftId, 0);
        assertEq(onChainOffer.asset, ZERO_ADDRESS);
        assertEq(onChainOffer.amount, 0);
        assertEq(onChainOffer.duration, 0);
        assertEq(onChainOffer.expiration, 0);
    }

    function testExecuteLoanByBorrower_works_in_eth() public {
        hevm.startPrank(LENDER_1);

        liquidityProviders.supplyEth{ value: 6 }();

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        uint256 borrowerEthBalanceBefore = address(this).balance;
        uint256 lenderEthBalanceBefore = address(LENDER_1).balance;

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(address(this).balance, borrowerEthBalanceBefore + 6);
        assertEq(cEtherToken.balanceOf(address(this)), 0);

        assertEq(address(LENDER_1).balance, lenderEthBalanceBefore);
        assertEq(cEtherToken.balanceOf(address(LENDER_1)), 0);

        assertEq(address(lendingAuction).balance, 0);
        assertEq(cEtherToken.balanceOf(address(lendingAuction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));
    }

    function testExecuteLoanByBorrower_event() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectEmit(true, false, false, true);

        emit LoanExecuted(LENDER_1, address(usdcToken), address(this), address(mockNft), 1, offer);

        emit AmountDrawn(address(this), address(mockNft), 1, 6, 6);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    // executeLoanByBorrowerSignature Tests

    function testCannotExecuteLoanByBorrowerSignature_asset_not_in_allow_list() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 12);
        usdcToken.approve(address(liquidityProviders), 12);

        liquidityProviders.supplyErc20(address(usdcToken), 12);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        liquidityProviders.setCAssetAddress(
            address(usdcToken),
            address(0x0000000000000000000000000000000000000000)
        );

        hevm.expectRevert("asset allow list");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    function testCannotExecuteLoanByBorrowerSignature_signature_blocked() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        offersContract.withdrawOfferSignature(offer, signature);

        hevm.stopPrank();

        hevm.expectRevert("signature not available");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 4);
    }

    function testCannotWithdrawOfferSignature_others_signature() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.stopPrank();

        hevm.prank(SIGNER_2);

        hevm.expectRevert("is not signer");

        offersContract.withdrawOfferSignature(offer, signature);
    }

    function testCannotExecuteLoanByBorrowerSignature_wrong_signer() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.stopPrank();

        hevm.expectRevert("offer creator mismatch");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_borrower_offer() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: false,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.stopPrank();

        hevm.expectRevert("lender offer");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_offer_expired() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.stopPrank();

        hevm.expectRevert("offer has expired");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_offer_duration() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.stopPrank();

        hevm.expectRevert("offer duration");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_not_owning_nft() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        mockNft.transferFrom(address(this), address(0x0000000000000000000000000000000000000001), 1);
        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.expectRevert("nft owner");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    function testCannotExecuteLoanByBorrowerSignature_not_enough_tokens() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.expectRevert("ERC20: burn amount exceeds balance");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    function testCannotExecuteLoanByBorrowerSignature_underlying_transfer_fails() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        usdcToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    function testCannotExecuteLoanByBorrowerSignature_eth_payment_fails() public {
        AddressUpgradeable.sendValue(payable(SIGNER_1), 6);

        hevm.startPrank(SIGNER_1);

        liquidityProviders.supplyEth{ value: 6 }();

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        acceptEth = false;

        hevm.expectRevert("Address: unable to send value, recipient may have reverted");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    function testExecuteLoanByBorrowerSignature_works_floor_term() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 12);
        usdcToken.approve(address(liquidityProviders), 12);

        liquidityProviders.supplyErc20(address(usdcToken), 12);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, SIGNER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 3);
        assertTrue(loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 1 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);

        // ensure that the offer is still there since its a floor offer
        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 2);
    }

    function testExecuteLoanByBorrowerSignature_works_not_floor_term() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 12);
        usdcToken.approve(address(liquidityProviders), 12);

        liquidityProviders.supplyErc20(address(usdcToken), 12);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, SIGNER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 3);
        assertTrue(loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 1 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);

        // ensure that the offer is gone
        hevm.expectRevert("signature not available");

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 2);
    }

    function testExecuteLoanByBorrowerSignature_works_in_eth() public {
        AddressUpgradeable.sendValue(payable(SIGNER_1), 6);
        hevm.startPrank(SIGNER_1);

        liquidityProviders.supplyEth{ value: 6 }();

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        uint256 borrowerEthBalanceBefore = address(this).balance;
        uint256 lenderEthBalanceBefore = address(SIGNER_1).balance;

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 1);

        assertEq(address(this).balance, borrowerEthBalanceBefore + 6);
        assertEq(cEtherToken.balanceOf(address(this)), 0);

        assertEq(address(SIGNER_1).balance, lenderEthBalanceBefore);
        assertEq(cEtherToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(address(lendingAuction).balance, 0);
        assertEq(cEtherToken.balanceOf(address(lendingAuction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));
    }

    function testExecuteLoanByBorrowerSignature_event() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 12);
        usdcToken.approve(address(liquidityProviders), 12);

        liquidityProviders.supplyErc20(address(usdcToken), 12);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.expectEmit(true, true, true, true);

        emit LoanExecuted(SIGNER_1, address(usdcToken), address(this), address(mockNft), 1, offer);

        emit AmountDrawn(address(this), address(mockNft), 1, 6, 6);

        emit OfferSignatureUsed(address(mockNft), 1, offer, signature);

        lendingAuction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    // executeLoanByLender Tests

    function testCannotExecuteLoanByLender_asset_not_in_allow_list() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        liquidityProviders.setCAssetAddress(
            address(usdcToken),
            address(0x0000000000000000000000000000000000000000)
        );

        hevm.expectRevert("asset allow list");

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_no_offer_present() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);
        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: false,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("no offer");

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);
        liquidityProviders.supplyErc20(address(usdcToken), 6);
        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        mockNft.transferFrom(address(this), SIGNER_1, 1);

        hevm.startPrank(SIGNER_1);
        mockNft.approve(address(lendingAuction), 1);
        hevm.stopPrank();

        hevm.startPrank(SIGNER_1);

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("offer has expired");

        hevm.stopPrank();

        hevm.warp(block.timestamp + 1 days);

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_offer_duration() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);
        liquidityProviders.supplyErc20(address(usdcToken), 6);
        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        mockNft.transferFrom(address(this), SIGNER_1, 1);

        hevm.startPrank(SIGNER_1);
        mockNft.approve(address(lendingAuction), 1);
        hevm.stopPrank();

        hevm.startPrank(SIGNER_1);

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("offer duration");

        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_not_owning_nft() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);
        liquidityProviders.supplyErc20(address(usdcToken), 6);
        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        mockNft.transferFrom(address(this), address(0x0000000000000000000000000000000000000001), 1);

        hevm.expectRevert("nft owner");

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_not_enough_tokens() public {
        hevm.startPrank(LENDER_2);
        usdcToken.mint(LENDER_2, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);
        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Insufficient cToken balance");

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_underlying_transfer_fails() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        usdcToken.setTransferFail(true);

        hevm.startPrank(LENDER_1);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_eth_payment_fails() public {
        hevm.startPrank(LENDER_1);

        liquidityProviders.supplyEth{ value: 6 }();

        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        acceptEth = false;

        hevm.expectRevert("Address: unable to send value, recipient may have reverted");

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_lender_offer() public {
        hevm.startPrank(LENDER_1);

        liquidityProviders.supplyEth{ value: 6 }();

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("borrower offer");

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);
        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.startPrank(LENDER_1);

        // TODO(miller): there was a TODO here, but not sure exactly what Daniel's intention with is was, some expected revert
        // hevm.expectRevert("foo");

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testExecuteLoanByLender_works_not_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 3);
        assertTrue(loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 1 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);

        // ensure that the offer is gone
        Offer memory onChainOffer = offersContract.getOffer(address(mockNft), 1, offerHash, false);

        assertEq(onChainOffer.creator, ZERO_ADDRESS);
        assertEq(onChainOffer.nftContractAddress, ZERO_ADDRESS);
        assertEq(onChainOffer.interestRatePerSecond, 0);
        assertTrue(!onChainOffer.fixedTerms);
        assertTrue(!onChainOffer.floorTerm);
        assertTrue(!onChainOffer.lenderOffer);
        assertEq(onChainOffer.nftId, 0);
        assertEq(onChainOffer.asset, ZERO_ADDRESS);
        assertEq(onChainOffer.amount, 0);
        assertEq(onChainOffer.duration, 0);
        assertEq(onChainOffer.expiration, 0);
    }

    function testExecuteLoanByLender_works_in_eth() public {
        hevm.startPrank(LENDER_1);

        liquidityProviders.supplyEth{ value: 6 }();

        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        uint256 borrowerEthBalanceBefore = address(this).balance;
        uint256 lenderEthBalanceBefore = address(LENDER_1).balance;

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(address(this).balance, borrowerEthBalanceBefore + 6);
        assertEq(cEtherToken.balanceOf(address(this)), 0);

        assertEq(address(LENDER_1).balance, lenderEthBalanceBefore);
        assertEq(cEtherToken.balanceOf(address(LENDER_1)), 0);

        assertEq(address(lendingAuction).balance, 0);
        assertEq(cEtherToken.balanceOf(address(lendingAuction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));
    }

    function testExecuteLoanByLender_event() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        hevm.stopPrank();

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectEmit(true, false, false, true);

        emit LoanExecuted(LENDER_1, address(usdcToken), address(this), address(mockNft), 1, offer);

        emit AmountDrawn(address(this), address(mockNft), 1, 6, 6);

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    // executeLoanByLenderSignature Tests

    function testCannotExecuteLoanByLenderSignature_asset_not_in_allow_list() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        mockNft.transferFrom(address(this), SIGNER_1, 1);

        hevm.startPrank(SIGNER_1);
        mockNft.approve(address(lendingAuction), 1);
        hevm.stopPrank();

        liquidityProviders.setCAssetAddress(
            address(usdcToken),
            address(0x0000000000000000000000000000000000000000)
        );

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.expectRevert("asset allow list");

        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_signature_blocked() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.stopPrank();
        hevm.startPrank(SIGNER_1);
        offersContract.withdrawOfferSignature(offer, signature);

        hevm.expectRevert("signature not available");
        hevm.stopPrank();
        hevm.startPrank(LENDER_1);
        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_wrong_signer() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.expectRevert("offer creator mismatch");

        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_lender_offer() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.stopPrank();

        hevm.expectRevert("borrower offer");

        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_offer_expired() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.stopPrank();

        hevm.expectRevert("offer has expired");

        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_offer_duration() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.stopPrank();

        hevm.expectRevert("offer duration");

        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_not_owning_nft() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.expectRevert("nft owner");

        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_not_enough_tokens() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        mockNft.transferFrom(address(this), SIGNER_1, 1);

        hevm.startPrank(SIGNER_1);
        mockNft.approve(address(lendingAuction), 1);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.expectRevert("ERC20: burn amount exceeds balance");

        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_underlying_transfer_fails() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        mockNft.transferFrom(address(this), SIGNER_1, 1);

        hevm.startPrank(SIGNER_1);
        mockNft.approve(address(lendingAuction), 1);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        usdcToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_eth_payment_fails() public {
        // TODO(miller): This is tough to test since we can not revert the signers
        //                 address on ETH transfers
        // can you look into this?
    }

    function testExecuteLoanByLenderSignature_works_not_floor_term() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        mockNft.transferFrom(address(this), SIGNER_1, 1);

        hevm.startPrank(SIGNER_1);
        mockNft.approve(address(lendingAuction), 1);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        lendingAuction.executeLoanByLenderSignature(offer, signature);

        assertEq(usdcToken.balanceOf(LENDER_1), 0);
        assertEq(cUSDCToken.balanceOf(LENDER_1), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 6);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), SIGNER_1);

        assertEq(liquidityProviders.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, SIGNER_1);
        assertEq(loanAuction.lender, LENDER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 3);
        assertTrue(loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 1 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);

        // ensure that the offer is gone
        hevm.expectRevert("signature not available");

        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    function testExecuteLoanByLenderSignature_works_in_eth() public {
        AddressUpgradeable.sendValue(payable(LENDER_1), 6);
        hevm.startPrank(LENDER_1);

        liquidityProviders.supplyEth{ value: 6 }();

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        mockNft.transferFrom(address(this), SIGNER_1, 1);

        hevm.startPrank(SIGNER_1);
        mockNft.approve(address(lendingAuction), 1);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        uint256 borrowerEthBalanceBefore = address(SIGNER_1).balance;
        uint256 lenderEthBalanceBefore = address(LENDER_1).balance;

        lendingAuction.executeLoanByLenderSignature(offer, signature);

        assertEq(address(SIGNER_1).balance, borrowerEthBalanceBefore + 6);
        assertEq(cEtherToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(address(LENDER_1).balance, lenderEthBalanceBefore);
        assertEq(cEtherToken.balanceOf(address(LENDER_1)), 0);

        assertEq(address(lendingAuction).balance, 0);
        assertEq(cEtherToken.balanceOf(address(lendingAuction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(SIGNER_1));
    }

    function testExecuteLoanByLenderSignature_event() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        mockNft.transferFrom(address(this), SIGNER_1, 1);

        hevm.startPrank(SIGNER_1);
        mockNft.approve(address(lendingAuction), 1);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer);

        hevm.expectEmit(true, true, true, true);

        emit LoanExecuted(LENDER_1, address(usdcToken), SIGNER_1, address(mockNft), 1, offer);

        emit AmountDrawn(SIGNER_1, address(mockNft), 1, 6, 6);

        emit OfferSignatureUsed(address(mockNft), 1, offer, signature);

        lendingAuction.executeLoanByLenderSignature(offer, signature);
    }

    // refinanceByBorrower Tests

    function testCannotRefinanceByBorrower_fixed_terms() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectRevert("fixed term loan");

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_min_duration() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days - 1,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectRevert("offer duration");

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_borrower_offer() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });
        hevm.stopPrank();
        offersContract.createOffer(offer2);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.expectRevert("lender offer");

        lendingAuction.refinanceByBorrower(address(mockNft), 1, false, offerHash2);
    }

    function testCannotRefinanceByBorrower_not_floor_term_mismatch_nftid() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectRevert("offer nftId mismatch");

        lendingAuction.refinanceByBorrower(address(mockNft), 3, false, offerHash2);
    }

    function testCannotRefinanceByBorrower_borrower_not_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.expectRevert("asset mismatch");

        lendingAuction.refinanceByBorrower(address(mockNft), 2, false, offerHash2);
    }

    function testCannotRefinanceByBorrower_no_open_loan() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        usdcToken.approve(address(liquidityProviders), 6);

        lendingAuction.repayLoan(address(mockNft), 1);

        hevm.expectRevert("asset mismatch");

        lendingAuction.refinanceByBorrower(address(mockNft), 2, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(liquidityProviders), 6);

        hevm.expectRevert("nft owner");

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_nft_contract_address() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(0x02),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(liquidityProviders), 6);

        hevm.expectRevert("offer nftId mismatch");

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_nft_id() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(liquidityProviders), 6);

        hevm.expectRevert("offer nftId mismatch");

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_wrong_asset() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        AddressUpgradeable.sendValue(payable(LENDER_2), 6);

        hevm.startPrank(LENDER_2);

        liquidityProviders.supplyEth{ value: 6 }();

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(liquidityProviders), 6);

        hevm.expectRevert("offer nftId mismatch");

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.warp(block.timestamp + 2);

        hevm.expectRevert("offer has expired");

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testRefinanceByBorrower_works() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 3 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(liquidityProviders.getCAssetBalance(LENDER_2, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_2);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 2);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);
    }

    function testRefinanceByBorrower_works_into_fix_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 3 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(liquidityProviders.getCAssetBalance(LENDER_2, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_2);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 2);
        assertTrue(loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);
    }

    function testRefinanceByBorrower_events() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 3 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectEmit(true, true, false, true);

        emit Refinance(LENDER_2, offer2.asset, address(this), address(mockNft), 1, offer2);

        emit AmountDrawn(address(this), offer.nftContractAddress, 1, 0, 6);

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_does_not_cover_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 200)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.warp(block.timestamp + 100);

        hevm.expectRevert("offer amount");

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testRefinanceByBorrower_covers_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444444, // 1% interest on 6 eth for 86400 seconds
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444442,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 200)
        });

        offersContract.createOffer(offer2);

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.warp(block.timestamp + 100);

        lendingAuction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6000069444444444400 ether
        );
        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            3999930555555555600 ether
        );

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_2);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 694444444442);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 7 ether);
        assertEq(loanAuction.loanEndTimestamp, loanAuction.loanBeginTimestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0); // 0 fee set so 0 balance expected
    }

    // refinanceByBorrowerSignature Tests

    function testCannotRefinanceByBorrowerSignature_fixed_terms() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.stopPrank();

        hevm.expectRevert("fixed term loan");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_withdrawn_signature() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        offersContract.withdrawOfferSignature(offer2, signature);

        hevm.stopPrank();

        hevm.expectRevert("signature not available");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_min_duration() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days - 1,
            expiration: uint32(block.timestamp + 1)
        });

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.stopPrank();

        hevm.expectRevert("offer duration");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_borrower_offer() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });
        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.expectRevert("lender offer");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_not_floor_term_mismatch_nftid() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.expectRevert("offer nftId mismatch");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_borrower_not_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.startPrank(BORROWER_1);

        hevm.expectRevert("nft owner");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_no_open_loan() public {
        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        mockNft.transferFrom(address(this), address(0x1), 1);
        hevm.expectRevert("asset mismatch");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_nft_contract_address() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(0x02),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.expectRevert("asset mismatch");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_nft_id() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.expectRevert("offer nftId mismatch");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_wrong_asset() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        AddressUpgradeable.sendValue(payable(SIGNER_1), 6);

        hevm.startPrank(SIGNER_1);

        liquidityProviders.supplyEth{ value: 6 }();

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.expectRevert("asset mismatch");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.warp(block.timestamp + 2);
        hevm.expectRevert("offer has expired");

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testRefinanceByBorrowerSignature_works_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 3 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(liquidityProviders.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, SIGNER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 2);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);

        // ensure the signature is not invalidated
        assertTrue(!offersContract.getOfferSignatureStatus(signature));
    }

    function testRefinanceByBorrowerSignature_works_not_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 3 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(liquidityProviders.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, SIGNER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 2);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);

        assertTrue(offersContract.getOfferSignatureStatus(signature));
    }

    function testRefinanceByBorrowerSignature_works_into_fix_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 3 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(liquidityProviders.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, SIGNER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 2);
        assertTrue(loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);
    }

    function testRefinanceByBorrowerSignature_events() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 3 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.expectEmit(true, true, true, true);

        emit OfferSignatureUsed(address(mockNft), 1, offer2, signature);

        emit Refinance(SIGNER_1, offer2.asset, address(this), address(mockNft), 1, offer2);

        emit AmountDrawn(address(this), offer.nftContractAddress, 1, 0, 6);

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_does_not_cover_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 200)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.expectRevert("offer amount");

        hevm.warp(block.timestamp + 100);

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testRefinanceByBorrowerSignature_covers_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444444, // 1% interest on 6 eth for 86400 seconds
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444442,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 200)
        });

        hevm.stopPrank();

        bytes memory signature = signOffer(SIGNER_PRIVATE_KEY_1, offer2);

        hevm.warp(block.timestamp + 100);

        lendingAuction.refinanceByBorrowerSignature(offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6000069444444444400 ether
        );
        assertEq(
            liquidityProviders.getCAssetBalance(SIGNER_1, address(cUSDCToken)),
            3999930555555555600 ether
        );

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, SIGNER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 694444444442);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 7 ether);
        assertEq(loanAuction.loanEndTimestamp, loanAuction.loanBeginTimestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0); // 0 fee set so 0 balance expected
    }

    // refinanceByLender Tests

    function testCannotRefinanceByLender_fixed_terms() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("fixed term loan");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testCannotRefinanceByLender_no_improvements_in_terms() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("not an improvement");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testCannotRefinanceByLender_borrower_offer() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.stopPrank();

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("lender offer");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testCannotRefinanceByLender_mismatch_nftid() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        hevm.startPrank(LENDER_2);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("loan not active");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testCannotRefinanceByLender_borrower_not_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("loan not active");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testCannotRefinanceByLender_no_open_loan() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        usdcToken.approve(address(liquidityProviders), 6);

        lendingAuction.repayLoan(address(mockNft), 1);

        hevm.startPrank(LENDER_2);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("loan not active");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testCannotRefinanceByLender_nft_contract_address() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(0x02),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("loan not active");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testCannotRefinanceByLender_nft_id() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("loan not active");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testCannotRefinanceByLender_wrong_asset() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        AddressUpgradeable.sendValue(payable(LENDER_2), 6);

        hevm.startPrank(LENDER_2);

        liquidityProviders.supplyEth{ value: 6 }();

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("asset mismatch");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testCannotRefinanceByLender_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.warp(block.timestamp + 2);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("offer has expired");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testCannotRefinanceByLender_if_sanctioned() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SANCTIONED_ADDRESS);
        usdcToken.mint(address(SANCTIONED_ADDRESS), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        // Cannot supplyErc20 as a sanctioned address.
        // This would actually revert here.
        // We can actually run this test without supplying any liquidity
        // because currently the sanctions check occurs before
        // checking to make sure the lender has sufficient balance
        // for the refinance offer.

        // lendingAuction.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: SANCTIONED_ADDRESS,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("sanctioned address");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testRefinanceByBorrower_works_different_lender() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 6844444400000,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 7 ether);
        usdcToken.approve(address(liquidityProviders), 7 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 7 ether);

        hevm.warp(block.timestamp + 12 hours);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 6844444400000,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 7 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6325679998080000000 ether
        );
        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            674320001920000000 ether
        );

        assertEq(liquidityProviders.getCAssetBalance(OWNER, address(cUSDCToken)), 0 ether);

        loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_2);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 6844444400000);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 7 ether);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 1 days - 12 hours);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 295679998080000000);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6 ether);
    }

    function testCannotRefinanceByLender_into_fixed_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 7 ether);
        usdcToken.approve(address(liquidityProviders), 7 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 7 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        hevm.expectRevert("fixed term offer");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testRefinanceByLender_events() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 6845444400000,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 7 ether);
        usdcToken.approve(address(liquidityProviders), 7 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 7 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 6844444400000,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether + 0.015 ether,
            duration: 1 days + 3.7 minutes,
            expiration: uint32(block.timestamp + 1)
        });
        hevm.expectEmit(true, true, false, true);

        emit Refinance(LENDER_2, offer2.asset, address(this), address(mockNft), 1, offer2);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testRefinanceByLender_covers_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444444,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        hevm.warp(block.timestamp + 6 hours + 10 minutes);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444440,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 200)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6045416666666656800 ether
        );
        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            3954583333333343200 ether
        );

        assertEq(
            liquidityProviders.getCAssetBalance(OWNER, address(cUSDCToken)),
            0 ether // premium at 0 so no balance expected
        );

        loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_2);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 694444444440);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 7 ether);
        assertEq(loanAuction.loanEndTimestamp, loanAuction.loanBeginTimestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 15416666666656800);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6000000000000000000);
    }

    function testRefinanceByLender_same_lender() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444444, // 1% interest on 6 eth for 86400 seconds
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444442,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 200)
        });

        hevm.warp(block.timestamp + 100);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            10000000000000000000 ether
        );

        assertEq(liquidityProviders.getCAssetBalance(OWNER, address(cUSDCToken)), 0);

        loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 694444444442);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6 ether);
        assertEq(loanAuction.loanEndTimestamp, loanAuction.loanBeginTimestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 69444444444400);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6 ether);
    }

    function testRefinanceByLender_covers_interest_3_lenders() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444444,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        hevm.warp(block.timestamp + 6 hours + 10 minutes);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444442,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 200)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);

        hevm.stopPrank();

        hevm.startPrank(LENDER_3);
        usdcToken.mint(address(LENDER_3), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        hevm.warp(block.timestamp + 6 hours + 10 minutes);

        Offer memory offer3 = Offer({
            creator: LENDER_3,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 694444444440,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 8 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 400)
        });

        loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer3, loanAuction.lastUpdatedTimestamp);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_3)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_3)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 20 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6045416666666656800 ether
        );
        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            10015416666666612400 ether
        );

        assertEq(
            liquidityProviders.getCAssetBalance(LENDER_3, address(cUSDCToken)),
            3939166666666730800 ether
        );

        assertEq(
            liquidityProviders.getCAssetBalance(OWNER, address(cUSDCToken)),
            0 ether // protocol premium is 0 so owner has no balance
        );

        loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_3);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 694444444440);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 8 ether);
        assertEq(loanAuction.loanEndTimestamp, loanAuction.loanBeginTimestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 30833333333269200);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6000000000000000000);
    }

    // TODO(miller): Missing test:
    //                 Refinance with different improvements same lender
    //                 Min duration update

    function testCannotSeizeAsset_asset_missing_in_allow_list() public {
        hevm.expectRevert("asset allow list");
        lendingAuction.seizeAsset(address(0x1), 6);
    }

    function testCannotSeizeAsset_no_open_loan() public {
        // We hit the same error here as if the asset was not whitelisted
        // we still leave the test in place
        hevm.expectRevert("asset allow list");
        lendingAuction.seizeAsset(address(mockNft), 1);
    }

    function testCannotSeizeAsset_loan_not_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // set time to one second before the loan will expire
        hevm.warp(block.timestamp + 1 days - 1);

        hevm.expectRevert("loan not expired");
        lendingAuction.seizeAsset(address(mockNft), 1);
    }

    function testCannotSeizeAsset_loan_repaid() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // set time to one second before the loan will expire
        hevm.warp(block.timestamp + 1 days - 1);

        usdcToken.mint(address(this), 6000 ether);
        usdcToken.approve(address(liquidityProviders), 6000 ether);

        lendingAuction.repayLoan(address(mockNft), 1);

        // empty lending auctions use zero asset
        hevm.expectRevert("asset allow list");
        lendingAuction.seizeAsset(address(mockNft), 1);
    }

    function testSeizeAsset_works() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.warp(block.timestamp + 1 days);

        lendingAuction.seizeAsset(address(mockNft), 1);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, ZERO_ADDRESS);
        assertEq(loanAuction.lender, ZERO_ADDRESS);
        assertEq(loanAuction.asset, ZERO_ADDRESS);
        assertEq(loanAuction.interestRatePerSecond, 0);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 0);
        assertEq(loanAuction.loanEndTimestamp, 0);
        assertEq(loanAuction.lastUpdatedTimestamp, 0);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 0);

        assertEq(mockNft.ownerOf(1), LENDER_1);
    }

    function testSeizeAsset_event() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.warp(block.timestamp + 1 days);

        hevm.expectEmit(true, false, false, true);

        emit AssetSeized(LENDER_1, address(this), address(mockNft), 1);

        lendingAuction.seizeAsset(address(mockNft), 1);
    }

    function testCannotRepayLoan_no_loan() public {
        hevm.expectRevert("asset allow list");
        lendingAuction.repayLoan(address(mockNft), 1);
    }

    function testCannotRepayLoan_someone_elses_loan() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(BORROWER_1);

        usdcToken.approve(address(liquidityProviders), 6);

        hevm.expectRevert("msg.sender is not the borrower");
        lendingAuction.repayLoan(offer.nftContractAddress, offer.nftId);
    }

    function testRepayLoan_works_no_interest_no_time() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(liquidityProviders), 6);

        liquidityProviders.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        usdcToken.approve(address(liquidityProviders), 6);

        lendingAuction.repayLoan(offer.nftContractAddress, offer.nftId);
    }

    function testRepayLoan_works_with_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(liquidityProviders), 6 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 1 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.warp(block.timestamp + 1 days);

        uint256 principal = 1 ether;

        (uint256 lenderInterest, uint256 protocolInterest) = lendingAuction
            .calculateInterestAccrued(offer.nftContractAddress, offer.nftId);

        uint256 repayAmount = principal + lenderInterest + protocolInterest;

        usdcToken.mint(address(this), lenderInterest + protocolInterest);

        usdcToken.approve(address(liquidityProviders), repayAmount);

        lendingAuction.repayLoan(offer.nftContractAddress, offer.nftId);

        assertEq(usdcToken.balanceOf(address(this)), 0);
        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(
            cUSDCToken.balanceOf(address(liquidityProviders)),
            (6 ether + lenderInterest + protocolInterest) * 1 ether
        );

        assertEq(mockNft.ownerOf(1), address(this));

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, ZERO_ADDRESS);
        assertEq(loanAuction.lender, ZERO_ADDRESS);
        assertEq(loanAuction.asset, ZERO_ADDRESS);
        assertEq(loanAuction.interestRatePerSecond, 0);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 0);
        assertEq(loanAuction.loanEndTimestamp, 0);
        assertEq(loanAuction.lastUpdatedTimestamp, 0);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 0);
    }

    function testDrawLoanAmount_works() public {
        setupRefinance();

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.amountDrawn, 6 ether);

        lendingAuction.drawLoanAmount(address(mockNft), 1, 5 * 10**17);

        assertEq(usdcToken.balanceOf(address(this)), 6.5 ether);

        loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.amountDrawn, 6.5 ether);
    }

    function testCannotDrawLoanAmount_funds_overdrawn() public {
        setupRefinance();

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.amountDrawn, 6 ether);

        hevm.expectRevert("funds overdrawn");

        lendingAuction.drawLoanAmount(address(mockNft), 1, 2 * 10**18);
    }

    function testCannotDrawLoanAmount_no_open_loan() public {
        setupRefinance();

        usdcToken.mint(address(this), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        lendingAuction.repayLoan(address(mockNft), 1);

        // TODO(miller) change NiftApes.sol so
        // that is "loan not active" is revert
        hevm.expectRevert("asset allow list");

        lendingAuction.drawLoanAmount(address(mockNft), 1, 2 * 10**18);
    }

    function testCannotDrawLoanAmount_not_your_loan() public {
        setupRefinance();

        hevm.expectRevert("nft owner");

        hevm.prank(SIGNER_1);

        lendingAuction.drawLoanAmount(address(mockNft), 1, 5 * 10**17);
    }

    function testCannotDrawLoanAmount_loan_expired() public {
        setupRefinance();

        hevm.warp(block.timestamp + 3 days);

        hevm.expectRevert("loan expired");

        lendingAuction.drawLoanAmount(address(mockNft), 1, 5 * 10**17);
    }

    function testRepayLoanForAccount_works() public {
        setupLoan();

        hevm.prank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 1000 ether);
        usdcToken.approve(address(liquidityProviders), 1000 ether);

        lendingAuction.repayLoanForAccount(address(mockNft), 1);
    }

    function testCannotRepayLoanForAccount_if_sanctioned() public {
        setupLoan();

        hevm.startPrank(SANCTIONED_ADDRESS);
        usdcToken.mint(address(SANCTIONED_ADDRESS), 1000 ether);
        usdcToken.approve(address(liquidityProviders), 1000 ether);

        hevm.expectRevert("sanctioned address");

        lendingAuction.repayLoanForAccount(address(mockNft), 1);
    }

    function testCannotRefinanceByLender_when_frontrunning_happens() public {
        // Note: Borrower and Lender 1 are colluding throughout
        // to extract fees from Lender 2

        // Also Note: assuming USDC has decimals 18 throughout
        // even though the real version has decimals 6
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);
        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        // Lender 1 has 10 USDC
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            10 ether
        );

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 1 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.stopPrank();

        // Borrower executes loan
        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // Lender 1 has 1 fewer USDC, i.e., 9
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            9 ether
        );

        // Warp ahead 12 hours
        hevm.warp(block.timestamp + 12 hours);

        // Lender 2 wants to refinance.
        // Given the current loan, they only expect
        // to pay an origination fee relative to 1 USDC draw amount
        // and no gas griefing fee
        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);
        hevm.stopPrank();

        // Lender 1 decides to frontrun Lender 2,
        // thereby 9x'ing the origination fee
        // and adding a gas griefing fee
        hevm.startPrank(LENDER_1);
        Offer memory frontrunner = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 9 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(frontrunner, loanAuction.lastUpdatedTimestamp);

        // Lender 1 has same 9 USDC
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            9 ether
        );

        hevm.stopPrank();

        // Borrower (colluding with Lender 1 and still frontrunning Lender 2)
        // draws full amount to maximize origination fee and gas griefing fee
        // that Lender 2 will pay Lender 1
        lendingAuction.drawLoanAmount(address(mockNft), 1, 8 ether);

        // After borrower draws rest, Lender 1 has 1 USDC
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            1 ether
        );

        hevm.startPrank(LENDER_2);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 9 ether + 1,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        // Not updating loanAuction, so this should be obsolete after frontrunning

        hevm.expectRevert("active loan is not as expected");

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);
    }

    function testRefinanceByLender_gas_griefing_fee_works() public {
        // Also Note: assuming USDC has decimals 18 throughout
        // even though the real version has decimals 6
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 1 ether);
        usdcToken.approve(address(liquidityProviders), 1 ether);
        liquidityProviders.supplyErc20(address(usdcToken), 1 ether);

        // Lender 1 has 10 USDC
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            1 ether
        );

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 10**10,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 1 ether,
            duration: 365 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.stopPrank();

        // Borrower executes loan
        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // Lender 1 has 1 fewer USDC, i.e., 9
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            0
        );

        // Warp ahead 10**5 seconds
        // 10**10 interest per second * 10**5 seconds = 10**15 interest
        // this is 0.001 of 10**18, which is under the gasGriefingBps of 25
        // which means there will be a gas griefing fee
        hevm.warp(block.timestamp + 10**5 seconds);

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 9 ether,
            duration: 365 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);

        hevm.stopPrank();

        // Below are calculations concerning how much Lender 1 has after fees
        // Note that gas griefing fee, if appicable, means we don't add interest,
        // since add whichever is greater, interest or gas griefing fee.
        uint256 principal = 1 ether;
        uint256 amtDrawn = 1 ether;
        uint256 originationFeeBps = 50;
        uint256 gasGriefingFeeBps = 25;
        uint256 MAX_BPS = 10_000;
        uint256 feesFromLender2 = ((amtDrawn * originationFeeBps) / MAX_BPS) +
            ((amtDrawn * gasGriefingFeeBps) / MAX_BPS);

        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            principal + feesFromLender2
        );
    }

    function testRefinanceByLender_no_gas_griefing_fee_if_sufficient_interest() public {
        // Also Note: assuming USDC has decimals 18 throughout
        // even though the real version has decimals 6
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 1 ether);
        usdcToken.approve(address(liquidityProviders), 1 ether);
        liquidityProviders.supplyErc20(address(usdcToken), 1 ether);

        // Lender 1 has 10 USDC
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            1 ether
        );

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 10**10,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 1 ether,
            duration: 365 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.stopPrank();

        // Borrower executes loan
        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // Lender 1 has 1 fewer USDC, i.e., 9
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            0
        );

        // Warp ahead 10**6 seconds
        // 10**10 interest per second * 10**6 seconds = 10**16 interest
        // this is 0.01 of 10**18, which is over the gasGriefingBps of 25
        // which means there won't be a gas griefing fee
        hevm.warp(block.timestamp + 10**6 seconds);

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 9 ether,
            duration: 365 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);

        hevm.stopPrank();

        // Below are calculations concerning how much Lender 1 has after fees

        uint256 principal = 1 ether;
        uint256 interest = 10**10 * 10**6;
        uint256 amtDrawn = 1 ether;
        uint256 originationFeeBps = 50;
        uint256 MAX_BPS = 10_000;
        uint256 feesFromLender2 = ((amtDrawn * originationFeeBps) / MAX_BPS);

        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            principal + interest + feesFromLender2
        );
    }

    function testRefinanceByLender_term_fee_works() public {
        // Also Note: assuming USDC has decimals 18 throughout
        // even though the real version has decimals 6
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 1 ether);
        usdcToken.approve(address(liquidityProviders), 1 ether);
        liquidityProviders.supplyErc20(address(usdcToken), 1 ether);

        // Lender 1 has 1 USDC
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            1 ether
        );

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 10_000_000_000,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 1 ether,
            duration: 365 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.stopPrank();

        // Borrower executes loan
        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // Lender 1 has 1 fewer USDC, i.e., 0
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            0
        );

        // Protocol owner has 0
        // Would have more later if there were a term fee
        // But will still have 0 if there isn't
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken))
            ),
            0
        );

        // Warp ahead 10**6 seconds
        // 10**10 interest per second * 10**6 seconds = 10**16 interest
        // this is 0.01 of 10**18, which is over the gas griefing amount of 0.0025
        // which means there won't be a gas griefing fee
        hevm.warp(block.timestamp + 10**6 seconds);

        hevm.startPrank(LENDER_2);

        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);
        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 9_974_000_000 + 1, // maximal improvment that still triggers term fee
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 1 ether,
            duration: 365 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);

        hevm.stopPrank();

        // Below are calculations concerning how much Lender 1 has after fees
        uint256 principal = 1 ether;
        uint256 interest = 10_000_000_000 * 10**6; // interest per second * seconds
        uint256 amtDrawn = 1 ether;
        uint256 originationFeeBps = 50;
        uint256 MAX_BPS = 10_000;
        uint256 feesFromLender2 = ((amtDrawn * originationFeeBps) / MAX_BPS);

        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            principal + interest + feesFromLender2
        );

        // Expect term griefing fee to have gone to protocol
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(OWNER, address(cUSDCToken))
            ),
            1 ether * 0.0025
        );
    }

    function testRefinanceByLender_term_fee_doesnt_apply_if_sufficient_improvement() public {
        // Also Note: assuming USDC has decimals 18 throughout
        // even though the real version has decimals 6
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 1 ether);
        usdcToken.approve(address(liquidityProviders), 1 ether);
        liquidityProviders.supplyErc20(address(usdcToken), 1 ether);

        // Lender 1 has 1 USDC
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            1 ether
        );

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 10_000_000_000,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 1 ether,
            duration: 365 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer);

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.stopPrank();

        // Borrower executes loan
        lendingAuction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // Lender 1 has 1 fewer USDC, i.e., 0
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            0
        );

        // Protocol owner has 0
        // Would have more later if there were a term fee
        // But will still have 0 if there isn't
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken))
            ),
            0
        );

        // Warp ahead 10**6 seconds
        // 10**10 interest per second * 10**6 seconds = 10**16 interest
        // this is 0.01 of 10**18, which is over the gas griefing amount of 0.0025
        // which means there won't be a gas griefing fee
        hevm.warp(block.timestamp + 10**6 seconds);

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(liquidityProviders), 10 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 9_974_000_000, // minimal improvment to avoid term griefing
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 1 ether,
            duration: 365 days,
            expiration: uint32(block.timestamp + 1)
        });

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        lendingAuction.refinanceByLender(offer2, loanAuction.lastUpdatedTimestamp);

        hevm.stopPrank();

        // Below are calculations concerning how much Lender 1 has after fees

        uint256 principal = 1 ether;
        uint256 interest = 10_000_000_000 * 10**6 seconds; // interest per second * seconds
        uint256 amtDrawn = 1 ether;
        uint256 originationFeeBps = 50;
        uint256 MAX_BPS = 10_000;
        uint256 feesFromLender2 = ((amtDrawn * originationFeeBps) / MAX_BPS);

        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(LENDER_1, address(cUSDCToken))
            ),
            principal + interest + feesFromLender2
        );

        // Expect no term griefing fee to have gone to protocol
        assertEq(
            liquidityProviders.cAssetAmountToAssetAmount(
                address(cUSDCToken),
                liquidityProviders.getCAssetBalance(OWNER, address(cUSDCToken))
            ),
            0
        );
    }

    function testDrawLoanAmount_slashUnsupportedAmount_works() public {
        setupRefinance();

        //increase block.timestamp to accumulate interest
        hevm.warp(block.timestamp + 12 hours);

        hevm.prank(LENDER_2);
        liquidityProviders.withdrawErc20(address(usdcToken), 0.9 ether);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);
        (uint256 lenderInterest, ) = lendingAuction.calculateInterestAccrued(address(mockNft), 1);
        uint256 lenderBalanceBefore = liquidityProviders.getCAssetBalance(
            LENDER_2,
            address(cUSDCToken)
        );

        assertEq(lenderInterest, 29999999999980800);
        assertEq(loanAuction.amountDrawn, 6 ether);
        assertTrue(loanAuction.lenderRefi);
        assertEq(lenderBalanceBefore, 40000000000019200000000000000000000);

        lendingAuction.drawLoanAmount(address(mockNft), 1, 1 ether);

        LoanAuction memory loanAuctionAfter = lendingAuction.getLoanAuction(address(mockNft), 1);
        (uint256 lenderInterestAfter, ) = lendingAuction.calculateInterestAccrued(
            address(mockNft),
            1
        );
        uint256 lenderBalanceAfter = liquidityProviders.getCAssetBalance(
            LENDER_2,
            address(cUSDCToken)
        );

        assertEq(lenderInterestAfter, 0);
        assertEq(lenderBalanceAfter, 0);
        // balance of the borrower
        assertEq(usdcToken.balanceOf(address(this)), 6040000000000019200);
        // we expect the amountDrawn to be 6.04x ether. This is the remaining balance of the lender plus the current amountdrawn
        assertEq(loanAuctionAfter.amountDrawn, 6040000000000019200);
        assertTrue(!loanAuctionAfter.lenderRefi);
    }

    // TODO(miller): More tests for regen collective percentage
    // TODO(miller): Tests for slashUnsupportedAmount
    // TODO(miller): Tests for interest math and dynamic interestRatePerSecond
    // TODO(miller): Tests for gas griefing preimum
    // TODO(miller): Tests for term griefing premium
    // TODO(miller): Review existing tests for additional cases
    // TODO(miller): Review contract functions and ensure there are tests for each function
    // TODO updateLendingContractAddress test
    // TODO updateLiquidityContractAddress test
    // TODO(captnseagraves): Add tests for lenderRefi in relevant functions
}
