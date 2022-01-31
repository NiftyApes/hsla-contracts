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
contract TestChainLendingAuction is DSTest, TestUtility, ERC721Holder {
    IUniswapV2Router SushiSwapRouter;
    MockERC721Token mockNFT;
    IWETH WETH;
    IERC20 DAI;
    ICERC20 cDAI;
    ICEther cETH;
    ChainLendingAuction chainLendingAuction;

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
        chainLendingAuction = new ChainLendingAuction();
        // Allow assets for testing
        chainLendingAuction.setCAssetAddress(address(DAI), address(cDAI));
        chainLendingAuction.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cETH)
        );
        uint256 max = type(uint256).max;

        // Setup mock NFT
        mockNFT = new MockERC721Token("BoredApe", "BAYC");

        // Give this contract some
        mockNFT.safeMint(address(this), 0);

        // Approve spends
        DAI.approve(address(chainLendingAuction), max);
        cDAI.approve(address(chainLendingAuction), max);
        cETH.approve(address(chainLendingAuction), max);

        // Supply to 10k DAI contract
        chainLendingAuction.supplyErc20(address(DAI), 100000 ether);
        // Supply 10 ether to contract
        chainLendingAuction.supplyEth{value: 10 ether}();
        // Offer NFT for sale
    }

    // Test Cases

    function testLoanDrawFeeProtocolPercentage() public {
        chainLendingAuction.loanDrawFeeProtocolPercentage();
    }

    function testBuyOutPremiumLenderPercentage() public {
        chainLendingAuction.buyOutPremiumLenderPercentage();
    }

    function testBuyOutPremiumProtocolPercentage() public {
        chainLendingAuction.buyOutPremiumProtocolPercentage();
    }

    function testUpdateLoanDrawFee() public {
        //TODO(parametic sweep)
        //TODO(Assert value)
        chainLendingAuction.updateLoanDrawFee(5);
    }

    function testUpdateBuyOutPremiumLenderPercentage() public {
        chainLendingAuction.updateBuyOutPremiumLenderPercentage(5);
    }

    function testUpdateBuyOutPremiumProtocolPercentage() public {
        chainLendingAuction.updateBuyOutPremiumProtocolPercentage(5);
    }
}
