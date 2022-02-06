// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./Console.sol";
import "ds-test/test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/compound/ICERC20.sol";
import "../interfaces/compound/ICEther.sol";
import "../LendingAuction.sol";
import "./Utilities.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

// @dev These tests are intended to be run against a forked mainnet.

// TODO(Refactor/deduplicate with LiquidityProviders testing)
contract TestLendingAuction is DSTest, TestUtility, ERC721Holder {
    IUniswapV2Router SushiSwapRouter;
    MockERC721Token mockNFT;
    IWETH WETH;
    Hevm IHEVM;
    IERC20 DAI;
    ICERC20 cDAI;
    ICEther cETH;
    LendingAuction LA;
    uint256 immutable pk =
        0x60b919c82f0b4791a5b7c6a7275970ace1748759ebdaa4076d7eeed9dbcff3c3;
    address immutable signer = 0x503408564C50b43208529faEf9bdf9794c015d52;

    function setUp() public {
        // Setup WETH
        WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        // Setup DAI
        DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

        // Setup SushiSwapRouter
        SushiSwapRouter = IUniswapV2Router(
            0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
        );

        // Setup cETH and balances
        cETH = ICEther(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
        // Mint some cETH
        cETH.mint{value: 10 ether}();

        // Setup HEVM
        IHEVM = Hevm(HEVM_ADDRESS);

        // Setup DAI balances

        // There is another way to do this using HEVM cheatcodes like so:
        //
        // IEVM.store(address(DAI), 0xde88c4128f6243399c8c224ee49c9683b554a068089998cb8cf2b7c8a19de28d, bytes32(uint256(100000 ether)));
        //
        // but I didn't figure out how to easily calculate the
        // storage addresses for the deployed test contracts or approvals, so I just used a deployed router.

        // So, we get some DAI with Sushiswap.
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(DAI);
        // Let's trade for 100k dai
        SushiSwapRouter.swapExactETHForTokens{value: 1000000 ether}(
            1000 ether,
            path,
            address(this),
            block.timestamp + 1000
        );

        // Setup cDAI and balances
        // Point at the real compound DAI token deployment
        cDAI = ICERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        // Mint 25 ether in cDAI
        DAI.approve(address(cDAI), 500000 ether);
        cDAI.mint(500000 ether);

        // Setup the liquidity providers contract
        LA = new LendingAuction();
        // Allow assets for testing
        LA.setCAssetAddress(address(DAI), address(cDAI));
        LA.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cETH)
        );
        uint256 max = type(uint256).max;

        // Setup mock NFT
        mockNFT = new MockERC721Token("BoredApe", "BAYC");

        // Give this contract some
        mockNFT.safeMint(address(this), 0);

        // Approve spends
        DAI.approve(address(LA), max);
        cDAI.approve(address(LA), max);
        cETH.approve(address(LA), max);

        // Supply to 10k DAI contract
        LA.supplyErc20(address(DAI), 100000 ether);
        // Supply 10 ether to contract
        LA.supplyEth{value: 10 ether}();
    }

    // Test Cases

    // TODO(Using a consistent unit of basis points here for the next 3 tests/6 interfaces would be more scrutable.)
    // Additionally, a basis points unit could let all 3 of these fit into one word of storage as uint64.
    // Addtionally, none of these really look like a "percentage".
    function testUpdateLoanDrawFee() public {
        // TODO(Why not just make the fee in basis points and get rid of the divisions?)
        LA.updateLoanDrawFee(50000);
        assert(LA.protocolDrawFeePercentage() == (50000 / 10000));
    }

    function testUpdateRefinancePremiumLenderPercentage() public {
        LA.updateRefinancePremiumLenderPercentage(500000);
        assert(LA.refinancePremiumLenderPercentage() == (500000 / 100000));
    }

    function testUpdateRefinancePremiumProtocolPercentage() public {
        LA.updateRefinancePremiumProtocolPercentage(5000);
        assert(LA.refinancePremiumProtocolPercentage() == (5000 / 1000));
    }

    function testCreateGetandRemoveOffer(bool fixedTerms, bool floorTerm)
        public
    {
        // Create a floor offer
        LendingAuction.Offer memory offer;
        offer.creator = address(this);
        offer.nftContractAddress = address(mockNFT);
        offer.nftId = 0;
        offer.asset = address(DAI);
        offer.amount = 25000 ether;
        offer.interestRate = 1000;
        offer.duration = 172800;
        offer.expiration = block.timestamp + 1000000;
        offer.fixedTerms = fixedTerms;
        offer.floorTerm = floorTerm;

        bytes32 create_hash = LA.getOfferHash(offer);

        LA.createOffer(offer);

        LendingAuction.Offer memory get_offer = LA.getOffer(
            address(mockNFT),
            0,
            create_hash,
            floorTerm
        );

        assert(LA.getOfferHash(get_offer) == create_hash);

        // And remove it
        LA.removeOffer(address(mockNFT), floorTerm, 0, create_hash);
    }

    function testSize(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm
    ) public {
        assert(0 == LA.size(nftContractAddress, nftId, floorTerm));
    }

    // TODO(This should pass)
    function testLoanAndRefinance(
        bool fixedTerms,
        bool floorTerm,
        bool lender
    ) public {
        // Create a floor offer
        LendingAuction.Offer memory offer;
        offer.creator = address(this);
        offer.nftContractAddress = address(mockNFT);
        offer.nftId = 0;
        offer.asset = address(DAI);
        offer.amount = 25000 ether;
        offer.interestRate = 1000;
        offer.duration = 172800;
        offer.expiration = block.timestamp + 1000000;
        offer.fixedTerms = fixedTerms;
        offer.floorTerm = floorTerm;

        bytes32 create_hash = LA.getOfferHash(offer);

        LA.createOffer(offer);

        mockNFT.approve(address(LA), 0);

        if (lender) {
            LA.executeLoanByLender(address(mockNFT), floorTerm, 0, create_hash);
        } else {
            LA.executeLoanByBorrower(
                address(mockNFT),
                floorTerm,
                0,
                create_hash
            );
        }

        // Let's move forward in time
        hevm.warp(block.number + 10000);

        LA.getLoanAuction(address(mockNFT), 0);

        offer.interestRate = offer.interestRate / 2;

        if (!offer.fixedTerms) {
            // Test refinance
            if (lender) {
                // TODO(Why is there an overflow here?)
                // LA.refinanceByLender(offer);
            } else {
                // TODO(This uses the incorrect interface to check who the owner of the nft is)
                hevm.prank(address(this), address(this));
                // LA.refinanceByBorrower(
                //    offer.nftContractAddress,
                //    offer.floorTerm,
                //    offer.nftId,
                //    create_hash
                //);
            }
        }
    }

    function testGetOfferSignatureAuctionStatus() public {
        // TODO(This is obviously an invalid offer, should the signature status return false)
        assert(!LA.getOfferSignatureStatus(""));
    }

    // TODO(Make this pass)
    function testFailGetOfferSigner() public {
        LendingAuction.Offer memory offer;
        offer.creator = address(this);
        offer.nftContractAddress = address(mockNFT);
        offer.nftId = 0;
        offer.asset = address(DAI);
        offer.amount = 25000 ether;
        offer.interestRate = 1000;
        offer.duration = 172800;
        offer.expiration = block.timestamp + 1000000;
        offer.fixedTerms = false;
        offer.floorTerm = false;

        bytes32 create_hash = LA.getOfferHash(offer);

        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = hevm.sign(pk, create_hash);

        // This produces a valid output:
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, create_hash));
        assert(signer == ecrecover(create_hash, v, r, s));

        bytes memory signature;

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

        // TODO(This does not.)
        // It appears to me that the implementation is incorrectly prefixing and encoding the message.
        // Implementation:
        // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol#L57
        // For an example from the VM traces...
        // It should be:
        // 0x0fd3a48c6f28bf8791b03f4efc946a3439527be41bc41fb97f21883d (as above in the working assertion)
        // But instead is:
        // 0xc565f2c525a69180b6390c4051dcab694179e1193d6200b4f974cb09
        // And thus the recovery of the original signer fails.
        // For some odd reason the contract implementation is mangling the signed message.
        assert(signer == LA.getOfferSigner(create_hash, signature));
    }
}
