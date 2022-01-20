// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "./console.sol";
import "ds-test/test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/compound/ICERC20.sol";
import "../interfaces/compound/ICEther.sol";
import "../SignatureLendingAuction.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

// @dev These tests are intended to be run against a forked mainnet.

contract Utility {
    function sendViaCall(address payable _to, uint256 amount) public payable {
        // Call returns a boolean value indicating success or failure.
        // This is the current recommended method to use.
        (bool sent, bytes memory data) = _to.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }
}

interface IWETH {
    function balanceOf(address) external returns (uint256);

    function deposit() external payable;
}

interface IUniswapV2Router {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

interface Ievm {
    // sets the block timestamp to x
    function warp(uint256 x) external;

    // sets the block number to x
    function roll(uint256 x) external;

    // sets the slot loc of contract c to val
    function store(
        address c,
        bytes32 loc,
        bytes32 val
    ) external;

    // reads the slot loc of contract c
    function load(address c, bytes32 loc) external returns (bytes32 val);
}

contract MockERC721Token is ERC721, ERC721Enumerable, Ownable {
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function safeMint(address to, uint256 tokenId) public onlyOwner {
        _safeMint(to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
    internal
    override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721, ERC721Enumerable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

// TODO(Refactor/deduplicate with LiquidityProviders testing)
contract TestSignatureLendingAuction is DSTest, Utility, ERC721Holder {
    Ievm IEVM;
    IUniswapV2Router SushiSwapRouter;
    MockERC721Token mockNFT;
    IWETH WETH;
    IERC20 DAI;
    ICERC20 cDAI;
    ICEther cETH;
    SignatureLendingAuction signatureLendingAuction;

    function setUp() public {
        // Setup cheat codes
        IEVM = Ievm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

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
        SushiSwapRouter.swapExactETHForTokens{value: 100000 ether}(
            100 ether,
            path,
            address(this),
            block.timestamp + 1000
        );

        // Setup cDAI and balances
        // Point at the real compound DAI token deployment
        cDAI = ICERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        // Mint 25 ether in cDAI
        DAI.approve(address(cDAI), 50000 ether);
        cDAI.mint(50000 ether);

        // Setup the liquidity providers contract
        signatureLendingAuction = new SignatureLendingAuction();
        // Allow assets for testing
        signatureLendingAuction.setCAssetAddress(address(DAI), address(cDAI));
        signatureLendingAuction.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cETH)
        );
        uint256 max = type(uint256).max;

        // Setup mock NFT
        mockNFT = new MockERC721Token("BoredApe", "BAYC");

        // Give this contract some
        mockNFT.safeMint(address(this), 0);

        // Approve spends
        DAI.approve(address(signatureLendingAuction), max);
        cDAI.approve(address(signatureLendingAuction), max);
        cETH.approve(address(signatureLendingAuction), max);

        // Supply to 10k DAI contract
        signatureLendingAuction.supplyErc20(address(DAI), 100000 ether);
        // Supply 10 ether to contract
        signatureLendingAuction.supplyEth{value: 10 ether}();
        // Offer NFT for sale
    }

    // Test Cases

    function testLoanDrawFeeProtocolPercentage() public {
        signatureLendingAuction.loanDrawFeeProtocolPercentage();
    }

    function testBuyOutPremiumLenderPercentage() public {
        signatureLendingAuction.buyOutPremiumLenderPercentage();
    }

    function testBuyOutPremiumProtocolPercentage() public {
        signatureLendingAuction.buyOutPremiumProtocolPercentage();
    }

    function testUpdateLoanDrawFee() public {
        //TODO(parametic sweep)
        //TODO(Assert value)
        signatureLendingAuction.updateLoanDrawFee(5);
    }

    function testUpdateBuyOutPremiumLenderPercentage() public {
        signatureLendingAuction.updateBuyOutPremiumLenderPercentage(5);
    }

    function testUpdateBuyOutPremiumProtocolPercentage() public {
        signatureLendingAuction.updateBuyOutPremiumProtocolPercentage(5);
    }





}