// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

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
    address constant LENDER_3 = address(0x3030);
    address constant BORROWER_1 = address(0x101);

    address constant OWNER = address(0xFFFFFFFFFFFFFF);

    uint256 immutable SIGNER_PRIVATE_KEY_1 =
        0x60b919c82f0b4791a5b7c6a7275970ace1748759ebdaa4076d7eeed9dbcff3c3;
    address immutable SIGNER_1 = 0x503408564C50b43208529faEf9bdf9794c015d52;

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

        lendingAction.transferOwnership(OWNER);
    }

    // TODO(dankurka): Move to base
    function signOffer(Offer memory offer) public returns (bytes memory) {
        // This is the EIP712 signed hash
        bytes32 encoded_offer = lendingAction.getOfferHash(offer);

        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = hevm.sign(SIGNER_PRIVATE_KEY_1, encoded_offer);

        bytes memory signature = "";

        // case 65: r,s,v signature (standard)
        assembly {
            // Logical shift left of the value
            mstore(add(signature, 0x20), r)
            mstore(add(signature, 0x40), s)
            mstore(add(signature, 0x60), shl(248, v))
            // 65 bytes long
            mstore(signature, 0x41)
            // Update free memory pointer
            mstore(0x40, add(signature, 0x80))
        }

        return signature;
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
        assertTrue(actual.lenderOffer);
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            4,
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
            lenderOffer: true,
            nftId: 4,
            asset: address(usdcToken),
            amount: 6,
            duration: 7,
            expiration: 8
        });

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectRevert("lender offer");

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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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

    function testCannotExecuteLoanByBorrower_borrower_offer() public {
        hevm.startPrank(LENDER_1);

        lendingAction.supplyEth{ value: 6 }();

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
        mockNft.approve(address(lendingAction), 1);

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectRevert("lender offer");

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testExecuteLoanByBorrower_works_floor_term() public {
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
            lenderOffer: true,
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

        // ensure that the offer is still there since its a floor offer

        Offer memory onChainOffer = lendingAction.getOffer(address(mockNft), 1, offerHash, true);

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
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        // ensure that the offer is gone
        Offer memory onChainOffer = lendingAction.getOffer(address(mockNft), 1, offerHash, false);

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

        lendingAction.supplyEth{ value: 6 }();

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
            lenderOffer: true,
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

        emit LoanExecuted(LENDER_1, address(usdcToken), address(this), address(mockNft), 1, offer);

        emit AmountDrawn(address(this), address(mockNft), 1, 6, 6);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrowerSignature_asset_not_in_allow_list() public {
        // TODO(dankurka): Can not write this test since we can not unlist
        // assets from the allow list and we need them to be in the list to add funds
    }

    function testCannotExecuteLoanByBorrowerSignature_signature_blocked() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        lendingAction.withdrawOfferSignature(offer, signature);

        hevm.stopPrank();

        hevm.expectRevert("signature not available");

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_wrong_signer() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.stopPrank();

        hevm.expectRevert("offer creator mismatch");

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_borrower_offer() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.stopPrank();

        hevm.expectRevert("lender offer");

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_offer_expired() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.stopPrank();

        hevm.expectRevert("offer expired");

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_offer_duration() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.stopPrank();

        hevm.expectRevert("offer duration");

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_not_owning_nft() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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
        bytes memory signature = signOffer(offer);

        hevm.expectRevert("nft owner");

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    function testCannotExecuteLoanByBorrowerSignature_not_enough_tokens() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.expectRevert("ERC20: burn amount exceeds balance");

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    function testCannotExecuteLoanByBorrowerSignature_underlying_transfer_fails() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        usdcToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    function testCannotExecuteLoanByBorrowerSignature_eth_payment_fails() public {
        AddressUpgradeable.sendValue(payable(SIGNER_1), 6);

        hevm.startPrank(SIGNER_1);

        lendingAction.supplyEth{ value: 6 }();

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

        bytes memory signature = signOffer(offer);

        acceptEth = false;

        hevm.expectRevert("Address: unable to send value, recipient may have reverted");

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    function testExecuteLoanByBorrowerSignature_works_floor_term() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 12);
        usdcToken.approve(address(lendingAction), 12);

        lendingAction.supplyErc20(address(usdcToken), 12);

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

        bytes memory signature = signOffer(offer);

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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
        lendingAction.executeLoanByBorrowerSignature(offer, signature, 2);
    }

    function testExecuteLoanByBorrowerSignature_works_not_floor_term() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 12);
        usdcToken.approve(address(lendingAction), 12);

        lendingAction.supplyErc20(address(usdcToken), 12);

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

        bytes memory signature = signOffer(offer);

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 2);
    }

    function testExecuteLoanByBorrowerSignature_works_in_eth() public {
        AddressUpgradeable.sendValue(payable(SIGNER_1), 6);
        hevm.startPrank(SIGNER_1);

        lendingAction.supplyEth{ value: 6 }();

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

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes memory signature = signOffer(offer);

        uint256 borrowerEthBalanceBefore = address(this).balance;
        uint256 lenderEthBalanceBefore = address(SIGNER_1).balance;

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 1);

        assertEq(address(this).balance, borrowerEthBalanceBefore + 6);
        assertEq(cEtherToken.balanceOf(address(this)), 0);

        assertEq(address(SIGNER_1).balance, lenderEthBalanceBefore);
        assertEq(cEtherToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(address(lendingAction).balance, 0);
        assertEq(cEtherToken.balanceOf(address(lendingAction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));
    }

    function testExecuteLoanByBorrowerSignature_event() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 12);
        usdcToken.approve(address(lendingAction), 12);

        lendingAction.supplyErc20(address(usdcToken), 12);

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

        bytes memory signature = signOffer(offer);

        hevm.expectEmit(true, true, true, true);

        emit LoanExecuted(SIGNER_1, address(usdcToken), address(this), address(mockNft), 1, offer);

        emit AmountDrawn(address(this), address(mockNft), 1, 6, 6);

        emit OfferSignatureUsed(address(mockNft), 1, offer, signature);

        lendingAction.executeLoanByBorrowerSignature(offer, signature, 1);
    }

    function testCannotExecuteLoanByLender_asset_not_in_allow_list() public {
        // TODO(dankurka): Can not write this test since we can not unlist
        // assets from the allow list and we need them to be in the list to add funds
    }

    function testCannotExecuteLoanByLender_no_offer_present() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);
        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectRevert("no offer");

        lendingAction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);
        lendingAction.supplyErc20(address(usdcToken), 6);
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
            expiration: 8
        });

        mockNft.transferFrom(address(this), SIGNER_1, 1);

        hevm.startPrank(SIGNER_1);
        mockNft.approve(address(lendingAction), 1);
        hevm.stopPrank();

        hevm.startPrank(SIGNER_1);

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectRevert("offer expired");

        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        lendingAction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_offer_duration() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);
        lendingAction.supplyErc20(address(usdcToken), 6);
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
        mockNft.approve(address(lendingAction), 1);
        hevm.stopPrank();

        hevm.startPrank(SIGNER_1);

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectRevert("offer duration");

        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        lendingAction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_not_owning_nft() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);
        lendingAction.supplyErc20(address(usdcToken), 6);
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

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        mockNft.transferFrom(address(this), address(0x0000000000000000000000000000000000000001), 1);

        hevm.expectRevert("nft owner");

        hevm.startPrank(LENDER_1);

        lendingAction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_not_enough_tokens() public {
        hevm.startPrank(LENDER_2);
        usdcToken.mint(LENDER_2, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);
        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Insufficient cToken balance");

        lendingAction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_underlying_transfer_fails() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        usdcToken.setTransferFail(true);

        hevm.startPrank(LENDER_1);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_eth_payment_fails() public {
        hevm.startPrank(LENDER_1);

        lendingAction.supplyEth{ value: 6 }();

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

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        acceptEth = false;

        hevm.expectRevert("Address: unable to send value, recipient may have reverted");

        hevm.startPrank(LENDER_1);

        lendingAction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_lender_offer() public {
        hevm.startPrank(LENDER_1);

        lendingAction.supplyEth{ value: 6 }();

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

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectRevert("borrower offer");

        lendingAction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);
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

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.startPrank(LENDER_1);

        // TODO
        // hevm.expectRevert("foo");

        lendingAction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testExecuteLoanByLender_works_not_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.startPrank(LENDER_1);

        lendingAction.executeLoanByLender(
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

        // ensure that the offer is gone
        Offer memory onChainOffer = lendingAction.getOffer(address(mockNft), 1, offerHash, false);

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

        lendingAction.supplyEth{ value: 6 }();

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

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        uint256 borrowerEthBalanceBefore = address(this).balance;
        uint256 lenderEthBalanceBefore = address(LENDER_1).balance;

        hevm.startPrank(LENDER_1);

        lendingAction.executeLoanByLender(
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

    function testExecuteLoanByLender_event() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.expectEmit(true, false, false, true);

        emit LoanExecuted(LENDER_1, address(usdcToken), address(this), address(mockNft), 1, offer);

        emit AmountDrawn(address(this), address(mockNft), 1, 6, 6);

        hevm.startPrank(LENDER_1);

        lendingAction.executeLoanByLender(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLenderSignature_asset_not_in_allow_list() public {
        // TODO(dankurka): Can not write this test since we can not unlist
        // assets from the allow list and we need them to be in the list to add funds
    }

    function testCannotExecuteLoanByLenderSignature_signature_blocked() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.stopPrank();
        hevm.startPrank(SIGNER_1);
        lendingAction.withdrawOfferSignature(offer, signature);

        hevm.expectRevert("signature not available");
        hevm.stopPrank();
        hevm.startPrank(LENDER_1);
        lendingAction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_wrong_signer() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.expectRevert("offer creator mismatch");

        lendingAction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_lender_offer() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.stopPrank();

        hevm.expectRevert("borrower offer");

        lendingAction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_offer_expired() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.stopPrank();

        hevm.expectRevert("offer expired");

        lendingAction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_offer_duration() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.stopPrank();

        hevm.expectRevert("offer duration");

        lendingAction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_not_owning_nft() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.expectRevert("nft owner");

        lendingAction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_not_enough_tokens() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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
        mockNft.approve(address(lendingAction), 1);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(offer);

        hevm.expectRevert("ERC20: burn amount exceeds balance");

        lendingAction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_underlying_transfer_fails() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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
        mockNft.approve(address(lendingAction), 1);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(offer);

        usdcToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAction.executeLoanByLenderSignature(offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_eth_payment_fails() public {
        // TODO(dankurka): This is tough to test since we can not revert the signers
        //                 address on ETH transfers
    }

    function testExecuteLoanByLenderSignature_works_not_floor_term() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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
        mockNft.approve(address(lendingAction), 1);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(offer);

        lendingAction.executeLoanByLenderSignature(offer, signature);

        assertEq(usdcToken.balanceOf(LENDER_1), 0);
        assertEq(cUSDCToken.balanceOf(LENDER_1), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 6);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), SIGNER_1);

        assertEq(lendingAction.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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

        lendingAction.executeLoanByLenderSignature(offer, signature);
    }

    function testExecuteLoanByLenderSignature_works_in_eth() public {
        AddressUpgradeable.sendValue(payable(LENDER_1), 6);
        hevm.startPrank(LENDER_1);

        lendingAction.supplyEth{ value: 6 }();

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
        mockNft.approve(address(lendingAction), 1);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(offer);

        uint256 borrowerEthBalanceBefore = address(SIGNER_1).balance;
        uint256 lenderEthBalanceBefore = address(LENDER_1).balance;

        lendingAction.executeLoanByLenderSignature(offer, signature);

        assertEq(address(SIGNER_1).balance, borrowerEthBalanceBefore + 6);
        assertEq(cEtherToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(address(LENDER_1).balance, lenderEthBalanceBefore);
        assertEq(cEtherToken.balanceOf(address(LENDER_1)), 0);

        assertEq(address(lendingAction).balance, 0);
        assertEq(cEtherToken.balanceOf(address(lendingAction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(SIGNER_1));
    }

    function testExecuteLoanByLenderSignature_event() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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
        mockNft.approve(address(lendingAction), 1);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        bytes memory signature = signOffer(offer);

        hevm.expectEmit(true, true, true, true);

        emit LoanExecuted(LENDER_1, address(usdcToken), SIGNER_1, address(mockNft), 1, offer);

        emit AmountDrawn(SIGNER_1, address(mockNft), 1, 6, 6);

        emit OfferSignatureUsed(address(mockNft), 1, offer, signature);

        lendingAction.executeLoanByLenderSignature(offer, signature);
    }

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
            lenderOffer: true,
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
            lenderOffer: true,
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

    function testCannotRefinanceByBorrower_min_duration() public {
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
            lenderOffer: true,
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days - 1,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectRevert("offer duration");

        lendingAction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_borrower_offer() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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
        lendingAction.createOffer(offer2);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.expectRevert("lender offer");

        lendingAction.refinanceByBorrower(address(mockNft), 1, false, offerHash2);
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.expectRevert("asset mismatch");

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
            lenderOffer: true,
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
            lenderOffer: true,
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

        hevm.expectRevert("asset mismatch");

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
            lenderOffer: true,
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
            lenderOffer: true,
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

    function testCannotRefinanceByBorrower_nft_contract_address() public {
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
            lenderOffer: true,
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

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(lendingAction), 6);

        hevm.expectRevert("offer nftId mismatch");

        lendingAction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_nft_id() public {
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
            lenderOffer: true,
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
            floorTerm: false,
            lenderOffer: true,
            nftId: 2,
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

        hevm.expectRevert("offer nftId mismatch");

        lendingAction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_wrong_asset() public {
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
            lenderOffer: true,
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

        AddressUpgradeable.sendValue(payable(LENDER_2), 6);

        hevm.startPrank(LENDER_2);

        lendingAction.supplyEth{ value: 6 }();

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

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(lendingAction), 6);

        hevm.expectRevert("offer nftId mismatch");

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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
        assertEq(lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(lendingAction.getCAssetBalance(LENDER_2, address(cUSDCToken)), 0);

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

    function testRefinanceByBorrower_works_into_fix_term() public {
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
            lenderOffer: true,
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
            fixedTerms: true,
            floorTerm: true,
            lenderOffer: true,
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
        assertEq(lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(lendingAction.getCAssetBalance(LENDER_2, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 3 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectEmit(true, true, false, true);

        emit Refinance(LENDER_2, offer2.asset, address(this), address(mockNft), 1, offer2);

        emit AmountDrawn(address(this), offer.nftContractAddress, 1, 0, 6);

        lendingAction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_does_not_cover_interest() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
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
        usdcToken.mint(address(LENDER_2), 6 ether);
        usdcToken.approve(address(lendingAction), 6 ether);

        lendingAction.supplyErc20(address(usdcToken), 6 ether);

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

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.warp(block.timestamp + 100);

        hevm.expectRevert("offer amount");

        lendingAction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);
    }

    function testRefinanceByBorrower_covers_interest() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
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
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(lendingAction), 10 ether);

        lendingAction.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 200)
        });

        lendingAction.createOffer(offer2);

        bytes32 offerHash2 = lendingAction.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.warp(block.timestamp + 100);

        lendingAction.refinanceByBorrower(address(mockNft), 1, true, offerHash2);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6000000000000001800 ether
        );
        assertEq(
            lendingAction.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            3999999999999998200 ether
        );

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_2);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 2);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 7 ether);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 30000);
        assertEq(loanAuction.amountDrawn, 6000000000000001800);
    }

    function testCannotRefinanceByBorrowerSignature_fixed_terms() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        hevm.stopPrank();

        hevm.expectRevert("fixed term loan");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_withdrawn_signature() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        lendingAction.withdrawOfferSignature(offer2, signature);

        hevm.stopPrank();

        hevm.expectRevert("signature not available");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_min_duration() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        hevm.stopPrank();

        hevm.expectRevert("offer duration");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_borrower_offer() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        hevm.expectRevert("lender offer");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_not_floor_term_mismatch_nftid() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        hevm.expectRevert("offer nftId mismatch");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_borrower_not_nft_owner() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        hevm.startPrank(BORROWER_1);

        hevm.expectRevert("nft owner");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_no_open_loan() public {
        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        mockNft.transferFrom(address(this), address(0x1), 1);
        hevm.expectRevert("asset mismatch");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_nft_contract_address() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        hevm.expectRevert("asset mismatch");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_nft_id() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        hevm.expectRevert("offer nftId mismatch");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_wrong_asset() public {
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
            lenderOffer: true,
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

        AddressUpgradeable.sendValue(payable(SIGNER_1), 6);

        hevm.startPrank(SIGNER_1);

        lendingAction.supplyEth{ value: 6 }();

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

        bytes memory signature = signOffer(offer2);

        hevm.expectRevert("asset mismatch");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_offer_expired() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        hevm.warp(block.timestamp + 2);
        hevm.expectRevert("offer expired");

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testRefinanceByBorrowerSignature_works_floor_term() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(lendingAction.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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
        assertTrue(!lendingAction.getOfferSignatureStatus(signature));
    }

    function testRefinanceByBorrowerSignature_works_not_floor_term() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(lendingAction.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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

        assertTrue(lendingAction.getOfferSignatureStatus(signature));
    }

    function testRefinanceByBorrowerSignature_works_into_fix_term() public {
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
            lenderOffer: true,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(lendingAction.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

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
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        lendingAction.createOffer(offer);

        hevm.stopPrank();

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAction), 6);

        lendingAction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer2);

        hevm.expectEmit(true, true, true, true);

        emit OfferSignatureUsed(address(mockNft), 1, offer2, signature);

        emit Refinance(SIGNER_1, offer2.asset, address(this), address(mockNft), 1, offer2);

        emit AmountDrawn(address(this), offer.nftContractAddress, 1, 0, 6);

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_does_not_cover_interest() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6 ether);
        usdcToken.approve(address(lendingAction), 6 ether);

        lendingAction.supplyErc20(address(usdcToken), 6 ether);

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

        bytes memory signature = signOffer(offer2);

        hevm.expectRevert("offer amount");

        hevm.warp(block.timestamp + 100);

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);
    }

    function testRefinanceByBorrowerSignature_covers_interest() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
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

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 10 ether);
        usdcToken.approve(address(lendingAction), 10 ether);

        lendingAction.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: SIGNER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
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

        bytes memory signature = signOffer(offer2);

        hevm.warp(block.timestamp + 100);

        lendingAction.refinanceByBorrowerSignature(offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6000000000000001800 ether
        );
        assertEq(
            lendingAction.getCAssetBalance(SIGNER_1, address(cUSDCToken)),
            3999999999999998200 ether
        );

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, SIGNER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 2);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 7 ether);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 30000);
        assertEq(loanAuction.amountDrawn, 6000000000000001800);
    }

    function testCannotRefinanceByLender_fixed_terms() public {
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
            lenderOffer: true,
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.expectRevert("fixed term loan");

        lendingAction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_no_improvements_in_terms() public {
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
            lenderOffer: true,
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

        hevm.expectRevert("not an improvement");

        lendingAction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_borrower_offer() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.createOffer(offer);

        bytes32 offerHash = lendingAction.getOfferHash(offer);

        hevm.stopPrank();

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
            lenderOffer: false,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        lendingAction.executeLoanByBorrower(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.expectRevert("lender offer");
        hevm.startPrank(LENDER_2);
        lendingAction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_mismatch_nftid() public {
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
            lenderOffer: true,
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
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        hevm.expectRevert("loan not active");
        hevm.startPrank(LENDER_2);
        lendingAction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_borrower_not_nft_owner() public {
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
            lenderOffer: true,
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
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.expectRevert("loan not active");

        lendingAction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_no_open_loan() public {
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
            lenderOffer: true,
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
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.stopPrank();

        usdcToken.approve(address(lendingAction), 6);

        lendingAction.repayLoan(address(mockNft), 1);

        hevm.expectRevert("loan not active");
        hevm.startPrank(LENDER_2);

        lendingAction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_nft_contract_address() public {
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
            lenderOffer: true,
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

        hevm.expectRevert("loan not active");

        lendingAction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_nft_id() public {
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
            lenderOffer: true,
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
            floorTerm: false,
            lenderOffer: true,
            nftId: 2,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.expectRevert("loan not active");

        lendingAction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_wrong_asset() public {
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
            lenderOffer: true,
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

        AddressUpgradeable.sendValue(payable(LENDER_2), 6);

        hevm.startPrank(LENDER_2);

        lendingAction.supplyEth{ value: 6 }();

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

        hevm.expectRevert("asset mismatch");

        lendingAction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_offer_expired() public {
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
            lenderOffer: true,
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
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        hevm.warp(block.timestamp + 2);

        hevm.expectRevert("offer expired");

        lendingAction.refinanceByLender(offer2);
    }

    function testRefinanceByBorrower_works_different_lender() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
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
        usdcToken.mint(address(LENDER_2), 7 ether);
        usdcToken.approve(address(lendingAction), 7 ether);

        lendingAction.supplyErc20(address(usdcToken), 7 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        lendingAction.refinanceByLender(offer2);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 7 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6030000000000000000 ether
        );
        assertEq(
            lendingAction.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            940000000000000000 ether
        );

        assertEq(
            lendingAction.getCAssetBalance(OWNER, address(cUSDCToken)),
            30000000000000000 ether
        );

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_2);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 3);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 7 ether);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 1 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 0);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6 ether);
    }

    function testCannotRefinanceByLender_into_fixed_term() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
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
        usdcToken.mint(address(LENDER_2), 7 ether);
        usdcToken.approve(address(lendingAction), 7 ether);

        lendingAction.supplyErc20(address(usdcToken), 7 ether);

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

        hevm.expectRevert("fixed term offer");

        lendingAction.refinanceByLender(offer2);
    }

    function testRefinanceByLender_events() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
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
        usdcToken.mint(address(LENDER_2), 7 ether);
        usdcToken.approve(address(lendingAction), 7 ether);

        lendingAction.supplyErc20(address(usdcToken), 7 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });
        hevm.expectEmit(true, true, false, true);

        emit Refinance(LENDER_2, offer2.asset, address(this), address(mockNft), 1, offer2);

        lendingAction.refinanceByLender(offer2);
    }

    function testRefinanceByLender_covers_interest() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
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
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(lendingAction), 10 ether);

        lendingAction.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 200)
        });

        hevm.warp(block.timestamp + 100);

        lendingAction.refinanceByLender(offer2);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6030000000000001800 ether
        );
        assertEq(
            lendingAction.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            3939999999999998200 ether
        );

        assertEq(
            lendingAction.getCAssetBalance(OWNER, address(cUSDCToken)),
            30000000000000000 ether
        );

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_2);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 2);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 7 ether);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 1800);
        assertEq(loanAuction.accumulatedProtocolInterest, 30000);
        assertEq(loanAuction.amountDrawn, 6000000000000000000);
    }

    function testRefinanceByLender_same_lender() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
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

        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 10 ether);
        usdcToken.approve(address(lendingAction), 10 ether);

        lendingAction.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 2,
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

        lendingAction.refinanceByLender(offer2);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            10000000000000000000 ether
        );

        assertEq(lendingAction.getCAssetBalance(OWNER, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_1);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 2);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 6 ether);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 1800);
        assertEq(loanAuction.accumulatedProtocolInterest, 30000);
        assertEq(loanAuction.amountDrawn, 6 ether);
    }

    function testRefinanceByLender_covers_interest_3_lenders() public {
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
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
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
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(lendingAction), 10 ether);

        lendingAction.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer2 = Offer({
            creator: LENDER_2,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 7 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 200)
        });

        hevm.warp(block.timestamp + 100);

        lendingAction.refinanceByLender(offer2);

        hevm.stopPrank();

        hevm.startPrank(LENDER_3);
        usdcToken.mint(address(LENDER_3), 10 ether);
        usdcToken.approve(address(lendingAction), 10 ether);

        lendingAction.supplyErc20(address(usdcToken), 10 ether);

        Offer memory offer3 = Offer({
            creator: LENDER_3,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 3,
            fixedTerms: false,
            floorTerm: false,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 8 ether,
            duration: 3 days,
            expiration: uint32(block.timestamp + 400)
        });

        hevm.warp(block.timestamp + 200);

        lendingAction.refinanceByLender(offer3);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_3)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_3)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAction)), 20 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAction));
        assertEq(lendingAction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6030000000000001800 ether
        );
        assertEq(
            lendingAction.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            9970000000000003600 ether
        );

        assertEq(
            lendingAction.getCAssetBalance(LENDER_3, address(cUSDCToken)),
            3939999999999994600 ether
        );

        assertEq(
            lendingAction.getCAssetBalance(OWNER, address(cUSDCToken)),
            60000000000000000 ether
        );

        LoanAuction memory loanAuction = lendingAction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_3);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 3);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 8 ether);
        assertEq(loanAuction.loanEndTimestamp, block.timestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 5400);
        assertEq(loanAuction.accumulatedProtocolInterest, 90000);
        assertEq(loanAuction.amountDrawn, 6000000000000000000);
    }

    // TODO(dankurka): Missing test:
    //                 Refinance with different improvements same lender
    //                 Min duration update

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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
            lenderOffer: true,
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
        uint256 lenderInterest = (3 * 1 days * principal) / 1 ether;
        uint256 protocolInterest = (50 * 1 days * principal) / 1 ether;

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

    // TODO(dankurka): Missing test for withdrawing someone elses signed offer
}
