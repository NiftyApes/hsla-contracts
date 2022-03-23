// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/interfaces/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../interfaces/compound/ICERC20.sol";
import "../../interfaces/compound/ICEther.sol";
import "../../NiftyApes.sol";
import "../../interfaces/niftyapes/lending/ILendingEvents.sol";

import "../common/BaseTest.sol";
import "../mock/CERC20Mock.sol";
import "../mock/CEtherMock.sol";
import "../mock/ERC20Mock.sol";
import "../mock/ERC721Mock.sol";

contract LendingAuctionUnitTest is
    BaseTest,
    ILendingEvents,
    ILendingStructs,
    ERC721HolderUpgradeable
{
    NiftyApes lendingAction;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    CEtherMock cEtherToken;

    ERC721Mock mockNft;

    bool acceptEth;

    address constant ZERO_ADDRESS = address(0);
    address constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address constant LENDER_1 = address(0x1010);
    address constant LENDER_2 = address(0x2020);
    address constant BORROWER_1 = address(0x101);

    receive() external payable {
        require(acceptEth, "acceptEth");
    }

    function setUp() public {
        lendingAction = new NiftyApes();
        lendingAction.initialize();

        usdcToken = new ERC20Mock();
        usdcToken.initialize("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock();
        cUSDCToken.initialize(usdcToken);
        lendingAction.setCAssetAddress(address(usdcToken), address(cUSDCToken));

        cEtherToken = new CEtherMock();
        cEtherToken.initialize();
        lendingAction.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        acceptEth = true;

        mockNft = new ERC721Mock();
        mockNft.initialize("BoredApe", "BAYC");

        mockNft.safeMint(address(this), 1);
        mockNft.approve(address(lendingAction), 1);

        mockNft.safeMint(address(this), 2);
        mockNft.approve(address(lendingAction), 2);
    }

    function testGetOffer_returns_empty_offer() public {
        Offer memory offer = lendingAction.getOffer(
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

    function testCannotCreateOffer_asset_not_whitelisted() public {
        Offer memory offer = Offer({
            creator: address(0x0000000000000000000000000000000000000001),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: false,
            nftId: 4,
            asset: address(0x0000000000000000000000000000000000000005),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        hevm.expectRevert("asset allow list");

        lendingAction.createOffer(offer);
    }

    function testCannotCreateOffer_offer_does_not_match_sender() public {
        Offer memory offer = Offer({
            creator: address(0x0000000000000000000000000000000000000001),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: false,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        hevm.expectRevert("offer creator");

        lendingAction.createOffer(offer);
    }

    function testCannotCreateOffer_not_enough_balance() public {
        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: false,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        hevm.expectRevert("Insufficient cToken balance");

        lendingAction.createOffer(offer);
    }

    function testCreateOffer_works() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        Offer memory actual = lendingAction.getOffer(
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
        assertEq(actual.nftId, 4);
        assertEq(actual.asset, address(usdcToken));
        assertEq(actual.amount, 6);
        assertEq(actual.duration, 7);
        assertEq(actual.expiration, 8);
    }

    function testCreateOffer_works_event() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectEmit(true, false, false, true);

        emit NewOffer(
            address(this),
            address(usdcToken),
            address(0x0000000000000000000000000000000000000002),
            4,
            offer,
            offerHash
        );

        lendingAction.createOffer(offer);
    }

    function testCannotRemoveOffer_other_user() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.prank(address(0x0000000000000000000000000000000000000001));

        hevm.expectRevert("offer creator");

        lendingAction.removeOffer(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testRemoveOffer_works() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.removeOffer(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        Offer memory actual = lendingAction.getOffer(
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
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectEmit(true, false, false, true);

        emit OfferRemoved(
            address(this),
            address(usdcToken),
            address(0x0000000000000000000000000000000000000002),
            offer,
            offerHash
        );

        lendingAction.removeOffer(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_asset_not_in_allow_list() public {
        // TODO(dankurka): Can not write this test since we can not unlist
        // assets from the allow list and we need them to be in the list to add funds
    }

    function testCannotExecuteLoanByBorrower_no_offer_present() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectRevert("no offer");

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_offer_expired() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectRevert("offer expired");

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_offer_duration() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectRevert("offer duration");

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_not_owning_nft() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        mockNft.transferFrom(address(this), address(0x0000000000000000000000000000000000000001), 1);

        hevm.expectRevert("nft owner");

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_not_enough_tokens() public {
        hevm.startPrank(LENDER_2);
        usdcToken.mint(LENDER_2, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);
        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer1 = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer1);

        bytes32 offerHash1 = lendingAction.getOfferHash(offer1);

        Offer memory offer2 = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        hevm.stopPrank();

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        // funds for first loan are available
        lendingAction.executeLoanByBorrower(
            offer1.nftContractAddress,
            offer1.nftId,
            offerHash1,
            offer1.floorTerm
        );

        hevm.expectRevert("Insufficient cToken balance");

        lendingAction.executeLoanByBorrower(
            offer2.nftContractAddress,
            offer2.nftId,
            offerHash2,
            offer2.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_underlying_transfer_fails() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        usdcToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_eth_payment_fails() public {
        hevm.startPrank(LENDER_1);

        lendingAction.supplyEth{ value: 6 }();

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        acceptEth = false;

        hevm.expectRevert("Address: unable to send value, recipient may have reverted");

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testExecuteLoanByBorrower_works() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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
    }

    function testExecuteLoanByBorrower_works_in_eth() public {
        hevm.startPrank(LENDER_1);

        lendingAction.supplyEth{ value: 6 }();

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        uint256 borrowerEthBalanceBefore = address(this).balance;
        uint256 lenderEthBalanceBefore = address(LENDER_1).balance;

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(address(this).balance, borrowerEthBalanceBefore + 6);
        assertEq(cEtherToken.balanceOf(address(this)), 0);

        assertEq(address(LENDER_1).balance, lenderEthBalanceBefore);
        assertEq(cEtherToken.balanceOf(address(LENDER_1)), 0);

        assertEq(address(lendingAction).balance, 0);
        assertEq(cEtherToken.balanceOf(address(lendingAction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));
    }

    function testExecuteLoanByBorrower_event() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectEmit(true, false, false, true);

        emit LoanExecuted(LENDER_1, address(this), address(mockNft), 1, offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    // TODO(dankurka): Tests missing for executeLoanByBorrowerSignature
    // TODO(dankurka): Tests missing for executeLoanByLender
    // TODO(dankurka): Tests missing for executeLoanByLenderSignature

    // TODO(dankurka): Tests around floor terms vs. not floor terms

    function testCannotRefinanceByBorrower_fixed_terms() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectRevert("fixed term loan");

        lendingAction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_not_floor_term_mismatch_nftid() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectRevert("offer nftId mismatch");

        lendingAction.refinanceByBorrower(address(mockNft), 3, false, offerHash2);
    }

    function testCannotRefinanceByBorrower_borrower_not_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.expectRevert("nft owner");

        lendingAction.refinanceByBorrower(address(mockNft), 2, false, offerHash2);
    }

    function testCannotRefinanceByBorrower_no_open_loan() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();

        usdcToken.approve(address(lendingAction), 6);

        lendingAction.repayLoan(address(mockNft), 1);

        hevm.expectRevert("nft owner");

        lendingAction.refinanceByBorrower(address(mockNft), 2, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(lendingAction), 6);

        hevm.expectRevert("nft owner");

        lendingAction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 1,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.warp(block.timestamp + 2);

        hevm.expectRevert("offer expired");

        lendingAction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testRefinanceByBorrower_works() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 3 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();

        lendingAction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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

    // TODO(dankurka): Lots of missing refinance test cases

    function testCannotSeizeAsset_asset_missing_in_allow_list() public {
        hevm.expectRevert("asset allow list");
        lendingAction.seizeAsset(address(0x1), 6);
    }

    function testCannotSeizeAsset_no_open_loan() public {
        // We hit the same error here as if the asset was not whitelisted
        // we still leave the test in place
        hevm.expectRevert("asset allow list");
        lendingAction.seizeAsset(address(mockNft), 1);
    }

    function testCannotSeizeAsset_loan_not_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // set time to one second before the loan will expire
        hevm.warp(block.timestamp + 1 days - 1);

        hevm.expectRevert("loan not expired");
        lendingAction.seizeAsset(address(mockNft), 1);
    }

    function testCannotSeizeAsset_loan_repaid() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // set time to one second before the loan will expire
        hevm.warp(block.timestamp + 1 days - 1);

        usdcToken.mint(address(this), 6000 ether);
        usdcToken.approve(address(lendingAction), 6000 ether);

        lendingAction.repayLoan(address(mockNft), 1);

        // empty lending auctions use zero asset
        hevm.expectRevert("asset allow list");
        lendingAction.seizeAsset(address(mockNft), 1);
    }

    function testSeizeAsset_works() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.warp(block.timestamp + 1 days);

        lendingAction.seizeAsset(address(mockNft), 1);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.warp(block.timestamp + 1 days);

        hevm.expectEmit(true, false, false, true);

        emit AssetSeized(LENDER_1, address(this), address(mockNft), 1);

        lendingAction.seizeAsset(address(mockNft), 1);
    }

    function testCannotRepayLoan_no_loan() public {
        hevm.expectRevert("asset allow list");
        lendingAction.repayLoan(address(mockNft), 1);
    }

    function testCannotRepayLoan_someone_elses_loan() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(BORROWER_1);

        usdcToken.approve(address(lendingAction), 6);

        hevm.expectRevert("msg.sender is not the borrower");
        lendingAction.repayLoan(offer.nftContractAddress, offer.nftId);
    }

    function testRepayLoan_works_no_interest_no_time() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        usdcToken.approve(address(lendingAction), 6);

        lendingAction.repayLoan(offer.nftContractAddress, offer.nftId);
    }

    function testRepayLoan_works_with_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAction), 6 ether);

        lendingAction.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 1 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.warp(block.timestamp + 1 days);

        uint256 principal = 1 ether;
        uint256 lenderInterest = (3 * 1 days * principal);
        uint256 protocolInterest = (50 * 1 days * principal);

        uint256 repayAmount = principal + lenderInterest + protocolInterest;

        usdcToken.mint(address(this), lenderInterest + protocolInterest);

        usdcToken.approve(address(lendingAction), repayAmount);

        lendingAction.repayLoan(offer.nftContractAddress, offer.nftId);

        assertEq(usdcToken.balanceOf(address(this)), 0);
        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(
            cUSDCToken.balanceOf(address(lendingAction)),
            (6 ether + lenderInterest + protocolInterest) * 1 ether
        );

        assertEq(
            cUSDCToken.balanceOf(address(lendingAction)),
            (6 ether + lenderInterest + protocolInterest) * 1 ether
        );

        assertEq(mockNft.ownerOf(1), address(this));

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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

    // TODO(dankurka): Tests missing for drawAmount

    // TODO(dankurka): Tests missing for drawTime

    function testCannotUpdateLoanDrawProtocolFee_not_owner() public {
        hevm.startPrank(LENDER_1);
        hevm.expectRevert("Ownable: caller is not the owner");
        lendingAction.updateLoanDrawProtocolFeePerSecond(1);
    }

    function testUpdateLoanDrawProtocolFee_owner() public {
        assertEq(lendingAction.loanDrawFeeProtocolPerSecond(), 50);
        lendingAction.updateLoanDrawProtocolFeePerSecond(1);
        assertEq(lendingAction.loanDrawFeeProtocolPerSecond(), 1);
    }

    function testCannotUpdateRefinancePremiumLenderFee_not_owner() public {
        hevm.startPrank(LENDER_1);
        hevm.expectRevert("Ownable: caller is not the owner");
        lendingAction.updateRefinancePremiumLenderFee(1);
    }

    function testCannotUpdateRefinancePremiumLenderFee_max_fee() public {
        hevm.expectRevert("max fee");
        lendingAction.updateRefinancePremiumLenderFee(1001);
    }

    function testPpdateRefinancePremiumLenderFee_owner() public {
        assertEq(lendingAction.refinancePremiumLenderBps(), 50);
        lendingAction.updateRefinancePremiumLenderFee(1);
        assertEq(lendingAction.refinancePremiumLenderBps(), 1);
    }

    function testCannotUpdateRefinancePremiumProtocolFee_not_owner() public {
        hevm.startPrank(LENDER_1);
        hevm.expectRevert("Ownable: caller is not the owner");
        lendingAction.updateRefinancePremiumProtocolFee(1);
    }

    function testCannotUpdateRefinancePremiumProtocolFee_max_fee() public {
        hevm.expectRevert("max fee");
        lendingAction.updateRefinancePremiumProtocolFee(1001);
    }

    function testUpdateRefinancePremiumProtocolFee_owner() public {
        assertEq(lendingAction.refinancePremiumProtocolBps(), 50);
        lendingAction.updateRefinancePremiumProtocolFee(1);
        assertEq(lendingAction.refinancePremiumProtocolBps(), 1);
    }
}
