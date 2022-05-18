// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../interfaces/compound/ICERC20.sol";
import "../../interfaces/compound/ICEther.sol";
import "../../NiftyApes.sol";
import "../../Offers.sol";
import "../../interfaces/niftyapes/lending/ILendingEvents.sol";
import "../../interfaces/niftyapes/offers/IOffersEvents.sol";

import "../common/BaseTest.sol";
import "../mock/CERC20Mock.sol";
import "../mock/CEtherMock.sol";
import "../mock/ERC20Mock.sol";
import "../mock/ERC721Mock.sol";
// import "../console.sol";


contract LendingAuctionUnitTest is
    BaseTest,
    ILendingEvents,
    ILendingStructs,
    IOffersEvents,
    IOffersStructs,
    ERC721HolderUpgradeable
{
    NiftyApes lendingAuction;
    NiftyApesOffers offersContract;
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
        lendingAuction = new NiftyApes();
        lendingAuction.initialize();

        offersContract = new NiftyApesOffers();
        offersContract.initialize();

        offersContract.updateLendingContractAddress(address(lendingAuction));

        usdcToken = new ERC20Mock();
        usdcToken.initialize("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock();
        cUSDCToken.initialize(usdcToken);
        lendingAuction.setCAssetAddress(address(usdcToken), address(cUSDCToken));

        cEtherToken = new CEtherMock();
        cEtherToken.initialize();
        lendingAuction.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
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

    // TODO(dankurka): Move to base
    function signOffer(Offer memory offer) public returns (bytes memory) {
        // This is the EIP712 signed hash
        bytes32 encoded_offer = offersContract.getOfferHash(offer);

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

        offersContract.createOffer(offer, address(lendingAuction));
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

        offersContract.createOffer(offer, address(lendingAuction));
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

        offersContract.createOffer(offer, address(lendingAuction));
    }

    function testCreateOffer_works() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

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
        assertEq(actual.expiration, 8);
    }

    function testCreateOffer_works_event() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        hevm.expectEmit(true, false, false, true);

        emit NewOffer(
            address(this),
            address(usdcToken),
            address(0x0000000000000000000000000000000000000002),
            4,
            offer,
            offerHash
        );

        offersContract.createOffer(offer, address(lendingAuction));
    }

    function testCannotRemoveOffer_other_user() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.prank(address(0x0000000000000000000000000000000000000001));

        hevm.expectRevert("offer creator");

        offersContract.removeOffer(
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testRemoveOffer_works() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

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

    function testCannotExecuteLoanByBorrower_asset_not_in_allow_list() public {
        // TODO(dankurka): Can not write this test since we can not unlist
        // assets from the allow list and we need them to be in the list to add funds
    }

    function testCannotExecuteLoanByBorrower_no_offer_present() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_offer_expired() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("offer expired");

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_offer_duration() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("offer duration");

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_not_owning_nft() public {
        usdcToken.mint(address(this), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        mockNft.transferFrom(address(this), address(0x0000000000000000000000000000000000000001), 1);

        hevm.expectRevert("nft owner");

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_not_enough_tokens() public {
        hevm.startPrank(LENDER_2);
        usdcToken.mint(LENDER_2, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);
        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer1, address(lendingAuction));

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

        offersContract.createOffer(offer2, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        // funds for first loan are available
        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer1.nftContractAddress,
            offer1.nftId,
            offerHash1,
            offer1.floorTerm
        );

        hevm.expectRevert("Insufficient cToken balance");

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer2.nftContractAddress,
            offer2.nftId,
            offerHash2,
            offer2.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_underlying_transfer_fails() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        usdcToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_eth_payment_fails() public {
        hevm.startPrank(LENDER_1);

        lendingAuction.supplyEth{ value: 6 }();

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        acceptEth = false;

        hevm.expectRevert("Address: unable to send value, recipient may have reverted");

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByBorrower_borrower_offer() public {
        hevm.startPrank(LENDER_1);

        lendingAuction.supplyEth{ value: 6 }();

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("lender offer");

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testExecuteLoanByBorrower_works_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);

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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);

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

        lendingAuction.supplyEth{ value: 6 }();

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        uint256 borrowerEthBalanceBefore = address(this).balance;
        uint256 lenderEthBalanceBefore = address(LENDER_1).balance;

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectEmit(true, false, false, true);

        emit LoanExecuted(LENDER_1, address(usdcToken), address(this), address(mockNft), 1, offer);

        emit AmountDrawn(address(this), address(mockNft), 1, 6, 6);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.withdrawOfferSignature(offer, signature);

        hevm.stopPrank();

        hevm.expectRevert("signature not available");

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_wrong_signer() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_borrower_offer() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_offer_expired() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_offer_duration() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 4);
    }

    function testCannotExecuteLoanByBorrowerSignature_not_owning_nft() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 1);
    }

    function testCannotExecuteLoanByBorrowerSignature_not_enough_tokens() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 1);
    }

    function testCannotExecuteLoanByBorrowerSignature_underlying_transfer_fails() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 1);
    }

    function testCannotExecuteLoanByBorrowerSignature_eth_payment_fails() public {
        AddressUpgradeable.sendValue(payable(SIGNER_1), 6);

        hevm.startPrank(SIGNER_1);

        lendingAuction.supplyEth{ value: 6 }();

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 1);
    }

    function testExecuteLoanByBorrowerSignature_works_floor_term() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 12);
        usdcToken.approve(address(lendingAuction), 12);

        lendingAuction.supplyErc20(address(usdcToken), 12);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);

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
        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 2);
    }

    function testExecuteLoanByBorrowerSignature_works_not_floor_term() public {
        hevm.startPrank(SIGNER_1);

        usdcToken.mint(SIGNER_1, 12);
        usdcToken.approve(address(lendingAuction), 12);

        lendingAuction.supplyErc20(address(usdcToken), 12);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 2);
    }

    function testExecuteLoanByBorrowerSignature_works_in_eth() public {
        AddressUpgradeable.sendValue(payable(SIGNER_1), 6);
        hevm.startPrank(SIGNER_1);

        lendingAuction.supplyEth{ value: 6 }();

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes memory signature = signOffer(offer);

        uint256 borrowerEthBalanceBefore = address(this).balance;
        uint256 lenderEthBalanceBefore = address(SIGNER_1).balance;

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 1);

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
        usdcToken.approve(address(lendingAuction), 12);

        lendingAuction.supplyErc20(address(usdcToken), 12);

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

        lendingAuction.executeLoanByBorrowerSignature(address(offersContract), offer, signature, 1);
    }

    function testCannotExecuteLoanByLender_asset_not_in_allow_list() public {
        // TODO(dankurka): Can not write this test since we can not unlist
        // assets from the allow list and we need them to be in the list to add funds
    }

    function testCannotExecuteLoanByLender_no_offer_present() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);
        lendingAuction.supplyErc20(address(usdcToken), 6);

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
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);
        lendingAuction.supplyErc20(address(usdcToken), 6);
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
        mockNft.approve(address(lendingAuction), 1);
        hevm.stopPrank();

        hevm.startPrank(SIGNER_1);

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("offer expired");

        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_offer_duration() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);
        lendingAuction.supplyErc20(address(usdcToken), 6);
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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("offer duration");

        hevm.stopPrank();

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_not_owning_nft() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);
        lendingAuction.supplyErc20(address(usdcToken), 6);
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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        mockNft.transferFrom(address(this), address(0x0000000000000000000000000000000000000001), 1);

        hevm.expectRevert("nft owner");

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_not_enough_tokens() public {
        hevm.startPrank(LENDER_2);
        usdcToken.mint(LENDER_2, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);
        hevm.stopPrank();

        hevm.startPrank(LENDER_1);
        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Insufficient cToken balance");

        lendingAuction.executeLoanByLender(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_underlying_transfer_fails() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        usdcToken.setTransferFail(true);

        hevm.startPrank(LENDER_1);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAuction.executeLoanByLender(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_eth_payment_fails() public {
        hevm.startPrank(LENDER_1);

        lendingAuction.supplyEth{ value: 6 }();

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        acceptEth = false;

        hevm.expectRevert("Address: unable to send value, recipient may have reverted");

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_lender_offer() public {
        hevm.startPrank(LENDER_1);

        lendingAuction.supplyEth{ value: 6 }();

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectRevert("borrower offer");

        lendingAuction.executeLoanByLender(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testCannotExecuteLoanByLender_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);
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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.startPrank(LENDER_1);

        // TODO
        // hevm.expectRevert("foo");

        lendingAuction.executeLoanByLender(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );
    }

    function testExecuteLoanByLender_works_not_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);

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

        lendingAuction.supplyEth{ value: 6 }();

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        uint256 borrowerEthBalanceBefore = address(this).balance;
        uint256 lenderEthBalanceBefore = address(LENDER_1).balance;

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            address(offersContract),
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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.expectEmit(true, false, false, true);

        emit LoanExecuted(LENDER_1, address(usdcToken), address(this), address(mockNft), 1, offer);

        emit AmountDrawn(address(this), address(mockNft), 1, 6, 6);

        hevm.startPrank(LENDER_1);

        lendingAuction.executeLoanByLender(
            address(offersContract),
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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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
        offersContract.withdrawOfferSignature(offer, signature);

        hevm.expectRevert("signature not available");
        hevm.stopPrank();
        hevm.startPrank(LENDER_1);
        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_wrong_signer() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_lender_offer() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_offer_expired() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_offer_duration() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_not_owning_nft() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_not_enough_tokens() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.expectRevert("ERC20: burn amount exceeds balance");

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_underlying_transfer_fails() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        usdcToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);
    }

    function testCannotExecuteLoanByLenderSignature_eth_payment_fails() public {
        // TODO(dankurka): This is tough to test since we can not revert the signers
        //                 address on ETH transfers
    }

    function testExecuteLoanByLenderSignature_works_not_floor_term() public {
        hevm.startPrank(LENDER_1);

        usdcToken.mint(LENDER_1, 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);

        assertEq(usdcToken.balanceOf(LENDER_1), 0);
        assertEq(cUSDCToken.balanceOf(LENDER_1), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 6);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 0);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), SIGNER_1);

        assertEq(lendingAuction.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

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

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);
    }

    function testExecuteLoanByLenderSignature_works_in_eth() public {
        AddressUpgradeable.sendValue(payable(LENDER_1), 6);
        hevm.startPrank(LENDER_1);

        lendingAuction.supplyEth{ value: 6 }();

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

        bytes memory signature = signOffer(offer);

        uint256 borrowerEthBalanceBefore = address(SIGNER_1).balance;
        uint256 lenderEthBalanceBefore = address(LENDER_1).balance;

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);

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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        bytes memory signature = signOffer(offer);

        hevm.expectEmit(true, true, true, true);

        emit LoanExecuted(LENDER_1, address(usdcToken), SIGNER_1, address(mockNft), 1, offer);

        emit AmountDrawn(SIGNER_1, address(mockNft), 1, 6, 6);

        emit OfferSignatureUsed(address(mockNft), 1, offer, signature);

        lendingAuction.executeLoanByLenderSignature(address(offersContract), offer, signature);
    }

    function testCannotRefinanceByBorrower_fixed_terms() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectRevert("fixed term loan");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_min_duration() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectRevert("offer duration");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_borrower_offer() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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
        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.expectRevert("lender offer");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, false, offerHash2);
    }

    function testCannotRefinanceByBorrower_not_floor_term_mismatch_nftid() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectRevert("offer nftId mismatch");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 3, false, offerHash2);
    }

    function testCannotRefinanceByBorrower_borrower_not_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.expectRevert("asset mismatch");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 2, false, offerHash2);
    }

    function testCannotRefinanceByBorrower_no_open_loan() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.repayLoan(address(mockNft), 1);

        hevm.expectRevert("asset mismatch");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 2, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(lendingAuction), 6);

        hevm.expectRevert("nft owner");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_nft_contract_address() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(lendingAuction), 6);

        hevm.expectRevert("offer nftId mismatch");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_nft_id() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(lendingAuction), 6);

        hevm.expectRevert("offer nftId mismatch");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_wrong_asset() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        AddressUpgradeable.sendValue(payable(LENDER_2), 6);

        hevm.startPrank(LENDER_2);

        lendingAuction.supplyEth{ value: 6 }();

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();
        hevm.startPrank(LENDER_1);

        usdcToken.approve(address(lendingAuction), 6);

        hevm.expectRevert("offer nftId mismatch");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.warp(block.timestamp + 2);

        hevm.expectRevert("offer expired");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);
    }

    function testRefinanceByBorrower_works() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(lendingAuction.getCAssetBalance(LENDER_2, address(cUSDCToken)), 0);

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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(lendingAuction.getCAssetBalance(LENDER_2, address(cUSDCToken)), 0);

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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.expectEmit(true, true, false, true);

        emit Refinance(LENDER_2, offer2.asset, address(this), address(mockNft), 1, offer2);

        emit AmountDrawn(address(this), offer.nftContractAddress, 1, 0, 6);

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);
    }

    function testCannotRefinanceByBorrower_does_not_cover_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.warp(block.timestamp + 100);

        hevm.expectRevert("offer amount");

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);
    }

    function testRefinanceByBorrower_covers_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(lendingAuction), 10 ether);

        lendingAuction.supplyErc20(address(usdcToken), 10 ether);

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

        offersContract.createOffer(offer2, address(lendingAuction));

        bytes32 offerHash2 = offersContract.getOfferHash(offer2);

        hevm.stopPrank();

        hevm.warp(block.timestamp + 100);

        lendingAuction.refinanceByBorrower(address(offersContract), address(mockNft), 1, true, offerHash2);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6000069444444444400 ether
        );
        assertEq(
            lendingAuction.getCAssetBalance(LENDER_2, address(cUSDCToken)),
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

    function testCannotRefinanceByBorrowerSignature_fixed_terms() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_withdrawn_signature() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.withdrawOfferSignature(offer2, signature);

        hevm.stopPrank();

        hevm.expectRevert("signature not available");

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_min_duration() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_borrower_offer() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_not_floor_term_mismatch_nftid() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_borrower_not_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_no_open_loan() public {
        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_nft_contract_address() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_nft_id() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_wrong_asset() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        AddressUpgradeable.sendValue(payable(SIGNER_1), 6);

        hevm.startPrank(SIGNER_1);

        lendingAuction.supplyEth{ value: 6 }();

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testRefinanceByBorrowerSignature_works_floor_term() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(lendingAuction.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(lendingAuction.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 6 ether);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)), 6 ether);
        assertEq(lendingAuction.getCAssetBalance(SIGNER_1, address(cUSDCToken)), 0);

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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testCannotRefinanceByBorrowerSignature_does_not_cover_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);
    }

    function testRefinanceByBorrowerSignature_covers_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(SIGNER_1);
        usdcToken.mint(address(SIGNER_1), 10 ether);
        usdcToken.approve(address(lendingAuction), 10 ether);

        lendingAuction.supplyErc20(address(usdcToken), 10 ether);

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

        bytes memory signature = signOffer(offer2);

        hevm.warp(block.timestamp + 100);

        lendingAuction.refinanceByBorrowerSignature(address(offersContract), offer2, signature, 1);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(SIGNER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(SIGNER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6000069444444444400 ether
        );
        assertEq(
            lendingAuction.getCAssetBalance(SIGNER_1, address(cUSDCToken)),
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

    function testCannotRefinanceByLender_fixed_terms() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_no_improvements_in_terms() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_borrower_offer() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        bytes32 offerHash = offersContract.getOfferHash(offer);

        hevm.stopPrank();

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.expectRevert("lender offer");
        hevm.startPrank(LENDER_2);
        lendingAuction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_mismatch_nftid() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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
        lendingAuction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_borrower_not_nft_owner() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_no_open_loan() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.repayLoan(address(mockNft), 1);

        hevm.expectRevert("loan not active");
        hevm.startPrank(LENDER_2);

        lendingAuction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_nft_contract_address() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_nft_id() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_wrong_asset() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        AddressUpgradeable.sendValue(payable(LENDER_2), 6);

        hevm.startPrank(LENDER_2);

        lendingAuction.supplyEth{ value: 6 }();

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

        lendingAuction.refinanceByLender(offer2);
    }

    function testCannotRefinanceByLender_offer_expired() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        lendingAuction.refinanceByLender(offer2);
    }

    function testRefinanceByBorrower_works_different_lender() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 7 ether);
        usdcToken.approve(address(lendingAuction), 7 ether);

        lendingAuction.supplyErc20(address(usdcToken), 7 ether);

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

        lendingAuction.refinanceByLender(offer2);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 7 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6030000000000000000 ether
        );
        assertEq(
            lendingAuction.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            970000000000000000 ether
        );

        assertEq(
            lendingAuction.getCAssetBalance(OWNER, address(cUSDCToken)),
            0 ether
        );

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

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
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 7 ether);
        usdcToken.approve(address(lendingAuction), 7 ether);

        lendingAuction.supplyErc20(address(usdcToken), 7 ether);

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

        lendingAuction.refinanceByLender(offer2);
    }

    function testRefinanceByLender_events() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

        Offer memory offer = Offer({
            creator: LENDER_1,
            nftContractAddress: address(mockNft),
            interestRatePerSecond: 6944444400000,
            fixedTerms: false,
            floorTerm: true,
            lenderOffer: true,
            nftId: 1,
            asset: address(usdcToken),
            amount: 6 ether,
            duration: 1 days,
            expiration: uint32(block.timestamp + 1)
        });

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 7 ether);
        usdcToken.approve(address(lendingAuction), 7 ether);

        lendingAuction.supplyErc20(address(usdcToken), 7 ether);

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
        hevm.expectEmit(true, true, false, true);

        emit Refinance(LENDER_2, offer2.asset, address(this), address(mockNft), 1, offer2);

        lendingAuction.refinanceByLender(offer2);
    }

    function testRefinanceByLender_covers_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(lendingAuction), 10 ether);

        lendingAuction.supplyErc20(address(usdcToken), 10 ether);

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

        hevm.warp(block.timestamp + 100);
        
        lendingAuction.refinanceByLender(offer2);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6030069444444444400 ether
        );
        assertEq(
            lendingAuction.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            3969930555555555600 ether
        );

        assertEq(
            lendingAuction.getCAssetBalance(OWNER, address(cUSDCToken)),
            0 ether // premium at 0 so no balance expected
        );

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_2);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 694444444440);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 7 ether);
        assertEq(loanAuction.loanEndTimestamp, loanAuction.loanBeginTimestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 69444444444400);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6000000000000000000);
    }

    function testRefinanceByLender_same_lender() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 10 ether);
        usdcToken.approve(address(lendingAuction), 10 ether);

        lendingAuction.supplyErc20(address(usdcToken), 10 ether);

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

        lendingAuction.refinanceByLender(offer2);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 10 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            10000000000000000000 ether
        );

        assertEq(lendingAuction.getCAssetBalance(OWNER, address(cUSDCToken)), 0);

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

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

    // TODO (captnseagraves) create tests that set the protocolInterestBps and refinancePremiumProtocolBps to higher vlaues and test math

    function testRefinanceByLender_covers_interest_3_lenders() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(LENDER_2);
        usdcToken.mint(address(LENDER_2), 10 ether);
        usdcToken.approve(address(lendingAuction), 10 ether);

        lendingAuction.supplyErc20(address(usdcToken), 10 ether);

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

        hevm.warp(block.timestamp + 100);

        lendingAuction.refinanceByLender(offer2);

        hevm.stopPrank();

        hevm.startPrank(LENDER_3);
        usdcToken.mint(address(LENDER_3), 10 ether);
        usdcToken.approve(address(lendingAuction), 10 ether);

        lendingAuction.supplyErc20(address(usdcToken), 10 ether);

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

        hevm.warp(block.timestamp + 200);

        lendingAuction.refinanceByLender(offer3);

        assertEq(usdcToken.balanceOf(address(this)), 6 ether);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_1)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_1)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_2)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_2)), 0);

        assertEq(usdcToken.balanceOf(address(LENDER_3)), 0);
        assertEq(cUSDCToken.balanceOf(address(LENDER_3)), 0);

        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(cUSDCToken.balanceOf(address(lendingAuction)), 20 ether * 10**18);

        assertEq(mockNft.ownerOf(1), address(lendingAuction));
        assertEq(lendingAuction.ownerOf(address(mockNft), 1), address(this));

        assertEq(lendingAuction.getCAssetBalance(address(this), address(cUSDCToken)), 0);
        assertEq(
            lendingAuction.getCAssetBalance(LENDER_1, address(cUSDCToken)),
            6030069444444444400 ether
        );
        assertEq(
            lendingAuction.getCAssetBalance(LENDER_2, address(cUSDCToken)),
            10000138888888888400 ether
        );

        assertEq(
            lendingAuction.getCAssetBalance(LENDER_3, address(cUSDCToken)),
            3969791666666667200 ether
        );

        assertEq(
            lendingAuction.getCAssetBalance(OWNER, address(cUSDCToken)),
            0 ether // protocol premium is 0 so owner has no balance
        );

        LoanAuction memory loanAuction = lendingAuction.getLoanAuction(address(mockNft), 1);

        assertEq(loanAuction.nftOwner, address(this));
        assertEq(loanAuction.lender, LENDER_3);
        assertEq(loanAuction.asset, address(usdcToken));
        assertEq(loanAuction.interestRatePerSecond, 694444444440);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 8 ether);
        assertEq(loanAuction.loanEndTimestamp, loanAuction.loanBeginTimestamp + 3 days);
        assertEq(loanAuction.lastUpdatedTimestamp, block.timestamp);
        assertEq(loanAuction.accumulatedLenderInterest, 208333333332800);
        assertEq(loanAuction.accumulatedProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 6000000000000000000);
    }

    // TODO(dankurka): Missing test:
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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        // set time to one second before the loan will expire
        hevm.warp(block.timestamp + 1 days - 1);

        usdcToken.mint(address(this), 6000 ether);
        usdcToken.approve(address(lendingAuction), 6000 ether);

        lendingAuction.repayLoan(address(mockNft), 1);

        // empty lending auctions use zero asset
        hevm.expectRevert("asset allow list");
        lendingAuction.seizeAsset(address(mockNft), 1);
    }

    function testSeizeAsset_works() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
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
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.startPrank(BORROWER_1);

        usdcToken.approve(address(lendingAuction), 6);

        hevm.expectRevert("msg.sender is not the borrower");
        lendingAuction.repayLoan(offer.nftContractAddress, offer.nftId);
    }

    function testRepayLoan_works_no_interest_no_time() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6);
        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.supplyErc20(address(usdcToken), 6);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        usdcToken.approve(address(lendingAuction), 6);

        lendingAuction.repayLoan(offer.nftContractAddress, offer.nftId);
    }

    function testRepayLoan_works_with_interest() public {
        hevm.startPrank(LENDER_1);
        usdcToken.mint(address(LENDER_1), 6 ether);
        usdcToken.approve(address(lendingAuction), 6 ether);

        lendingAuction.supplyErc20(address(usdcToken), 6 ether);

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

        offersContract.createOffer(offer, address(lendingAuction));

        hevm.stopPrank();

        bytes32 offerHash = offersContract.getOfferHash(offer);

        lendingAuction.executeLoanByBorrower(
            address(offersContract),
            offer.nftContractAddress,
            offer.nftId,
            offerHash,
            offer.floorTerm
        );

        hevm.warp(block.timestamp + 1 days);

        uint256 principal = 1 ether;

        (uint256 lenderInterest, uint256 protocolInterest) = lendingAuction.calculateInterestAccrued(offer.nftContractAddress, offer.nftId);

        uint256 repayAmount = principal + lenderInterest + protocolInterest;

        usdcToken.mint(address(this), lenderInterest + protocolInterest);

        usdcToken.approve(address(lendingAuction), repayAmount);

        lendingAuction.repayLoan(offer.nftContractAddress, offer.nftId);

        assertEq(usdcToken.balanceOf(address(this)), 0);
        assertEq(usdcToken.balanceOf(address(lendingAuction)), 0);
        assertEq(
            cUSDCToken.balanceOf(address(lendingAuction)),
            (6 ether + lenderInterest + protocolInterest) * 1 ether
        );

        assertEq(
            cUSDCToken.balanceOf(address(lendingAuction)),
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

    // TODO(dankurka): Tests missing for drawAmount

    // TODO(dankurka): Missing test for withdrawing someone elses signed offer

    // TODO(captnseagraves): Missing tests for regen collective percentage

    // TODO(captnseagraves): Missing tests for Sanctions list

}
