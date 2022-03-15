// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./Console.sol";
import "ds-test/test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "../interfaces/compound/ICERC20.sol";
import "../interfaces/compound/ICEther.sol";
import "../LendingAuction.sol";
import "../interfaces/ILendingAuctionEvents.sol";
import "../Exponential.sol";
import "./Utilities.sol";

import "./mock/CERC20Mock.sol";
import "./mock/CEtherMock.sol";
import "./mock/ERC20Mock.sol";

contract LendingAuctionUnitTest is
    DSTest,
    TestUtility,
    Exponential,
    ILendingAuctionEvents,
    ILendingAuctionStructs,
    ERC721Holder
{
    LendingAuction lendingAction;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    CEtherMock cEtherToken;

    MockERC721Token mockNft;

    bool acceptEth;

    address constant ZERO_ADDRESS = address(0);
    address constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address constant LENDER_1 = address(0x1010);
    address constant LENDER_2 = address(0x2020);

    receive() external payable {
        require(acceptEth, "acceptEth");
    }

    function setUp() public {
        lendingAction = new LendingAuction();

        usdcToken = new ERC20Mock("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock(usdcToken);
        lendingAction.setCAssetAddress(address(usdcToken), address(cUSDCToken));

        cEtherToken = new CEtherMock();
        lendingAction.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        acceptEth = true;

        mockNft = new MockERC721Token("BoredApe", "BAYC");

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
        assertEq(offer.interestRateBps, 0);
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
            interestRateBps: 3,
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
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: false,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        hevm.expectRevert("creator != sender");

        lendingAction.createOffer(offer);
    }

    function testCannotCreateOffer_not_enough_balance() public {
        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: false,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        hevm.expectRevert("Insufficient lender balance");

        lendingAction.createOffer(offer);
    }

    function testCreateOffer_works() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: address(this),
            nftContractAddress: address(0x0000000000000000000000000000000000000002),
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

        Offer memory actual = lendingAction.getOffer(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(actual.creator, address(this));
        assertEq(actual.nftContractAddress, address(0x0000000000000000000000000000000000000002));
        assertEq(actual.interestRateBps, 3);
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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

        hevm.prank(address(0x0000000000000000000000000000000000000001));

        hevm.expectRevert("wrong offer creator");

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
        assertEq(actual.interestRateBps, 0);
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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer1);

        bytes32 offerHash1 = lendingAction.getEIP712EncodedOffer(offer1);

        Offer memory offer2 = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer2);

        hevm.stopPrank();

        bytes32 offerHash2 = lendingAction.getEIP712EncodedOffer(offer2);

        // funds for first loan are available
        lendingAction.executeLoanByBorrower(
            offer1.nftContractAddress,
            offer1.nftId,
            offerHash1,
            offer1.floorTerm
        );

        hevm.expectRevert("Insuffient ctoken balance");

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
        assertEq(loanAuction.interestRateBps, 3);
        assertTrue(loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.duration, 1 days);
        assertEq(loanAuction.timeOfInterestStart, block.timestamp);
        assertEq(loanAuction.historicLenderInterest, 0);
        assertEq(loanAuction.historicProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);
        assertEq(loanAuction.timeDrawn, 1 days);
    }

    function testExecuteLoanByBorrower_works_in_eth() public {
        hevm.startPrank(LENDER_1);

        lendingAction.supplyEth{ value: 6 }();

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: ETH_ADDRESS,
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: true,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 2,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getEIP712EncodedOffer(offer2);

        hevm.stopPrank();

        hevm.expectRevert("fixed term loan");

        lendingAction.refinanceByBorrower(address(mockNft), true, 1, offerHash2);
    }

    function testCannotRefinanceByBorrower_not_floor_term_mismatch_nftid() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 2,
            fixedTerms: false,
            floorTerm: false,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getEIP712EncodedOffer(offer2);

        hevm.stopPrank();

        hevm.expectRevert("offer nftId mismatch");

        lendingAction.refinanceByBorrower(address(mockNft), false, 3, offerHash2);
    }

    function testCannotRefinanceByBorrower_borrower_not_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 2,
            fixedTerms: false,
            floorTerm: false,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getEIP712EncodedOffer(offer2);

        hevm.expectRevert("nft owner");

        lendingAction.refinanceByBorrower(address(mockNft), false, 2, offerHash2);
    }

    function testCannotRefinanceByBorrower_no_open_loan() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 1,
            fixedTerms: false,
            floorTerm: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getEIP712EncodedOffer(offer2);

        hevm.stopPrank();

        usdcToken.approve(address(lendingAction), 6);

        lendingAction.repayLoan(address(mockNft), 1);

        hevm.expectRevert("nft owner");

        lendingAction.refinanceByBorrower(address(mockNft), true, 2, offerHash2);
    }

    function testCannotRefinanceByBorrower_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 1,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getEIP712EncodedOffer(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(lendingAction), 6);

        hevm.expectRevert("nft owner");

        lendingAction.refinanceByBorrower(address(mockNft), true, 1, offerHash2);
    }

    function testCannotRefinanceByBorrower_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 1,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getEIP712EncodedOffer(offer2);

        hevm.stopPrank();

        hevm.warp(block.timestamp + 2);

        hevm.expectRevert("offer expired");

        lendingAction.refinanceByBorrower(address(mockNft), true, 1, offerHash2);
    }

    function testRefinanceByBorrower_works() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 2,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 3 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getEIP712EncodedOffer(offer2);

        hevm.stopPrank();

        lendingAction.refinanceByBorrower(address(mockNft), true, 1, offerHash2);

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
        assertEq(loanAuction.interestRateBps, 2);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6);
        assertEq(loanAuction.duration, 3 days);
        assertEq(loanAuction.timeOfInterestStart, block.timestamp);
        assertEq(loanAuction.historicLenderInterest, 0);
        assertEq(loanAuction.historicProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6);
        assertEq(loanAuction.timeDrawn, 1 days);
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
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // set time to one second before the loan will expire
        hevm.warp(block.timestamp + 1 days - 1);

        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAction), 6);

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
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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
        assertEq(loanAuction.interestRateBps, 0);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 0);
        assertEq(loanAuction.duration, 0);
        assertEq(loanAuction.timeOfInterestStart, 0);
        assertEq(loanAuction.historicLenderInterest, 0);
        assertEq(loanAuction.historicProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 0);
        assertEq(loanAuction.timeDrawn, 0);

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
            interestRateBps: 3,
            fixedTerms: false,
            floorTerm: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: block.timestamp + 1
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getEIP712EncodedOffer(offer);

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

    // TODO(dankurka): Tests missing for drawAmount

    // TODO(dankurka): Tests missing for drawTime

    function testCannotUpdateLoanDrawProtocolFee_not_owner() public {
        hevm.startPrank(LENDER_1);
        hevm.expectRevert("Ownable: caller is not the owner");
        lendingAction.updateLoanDrawProtocolFee(1);
    }

    function testCannotUpdateLoanDrawProtocolFee_max_fee() public {
        hevm.expectRevert("max fee");
        lendingAction.updateLoanDrawProtocolFee(1001);
    }

    function testUpdateLoanDrawProtocolFee_owner() public {
        assertEq(lendingAction.loanDrawFeeProtocolBps(), 50);
        lendingAction.updateLoanDrawProtocolFee(1);
        assertEq(lendingAction.loanDrawFeeProtocolBps(), 1);
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
