// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./Console.sol";
import "ds-test/test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/compound/ICERC20.sol";
import "../interfaces/compound/ICEther.sol";
import "../LiquidityProviders.sol";
import "./Utilities.sol";

// @dev These tests are intended to be run against a forked mainnet.

contract LiquidityProvidersTest is DSTest, TestUtility {
    IUniswapV2Router SushiSwapRouter;
    IWETH WETH;
    IERC20 DAI;
    ICERC20 cDAI;
    ICEther cETH;
    LiquidityProviders liquidityProviders;

    // This is needed to receive ETH when calling `withdrawEth`
    receive() external payable {}

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
        liquidityProviders = new LiquidityProviders();
        // Allow assets for testing
        liquidityProviders.setCAssetAddress(address(DAI), address(cDAI));
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cETH)
        );
        uint256 max = type(uint256).max;

        // Approve spends
        DAI.approve(address(liquidityProviders), max);
        cDAI.approve(address(liquidityProviders), max);
        cETH.approve(address(liquidityProviders), max);

        // Supply to 10k DAI contract
        liquidityProviders.supplyErc20(address(DAI), 100000 ether);
        // Supply 10 ether to contract
        liquidityProviders.supplyEth{value: 10 ether}();
    }

    // Test cases

    function testBalances() public {
        // Just to make sure all our balances got set during setup
        assert(DAI.balanceOf(address(this)) > 0);
        assert(cDAI.balanceOf(address(this)) > 0);
        assert(address(this).balance > 0);
    }

    function testAssetToCAsset() public {
        assert(
            liquidityProviders.assetToCAsset(
                address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
            ) == address(cETH)
        );
    }

    function testCAssetBalances() public {
        assert(
            liquidityProviders.cAssetBalances(address(cDAI), address(this)) >
                0 ether
        );
    }

    function testUtilizedCAssetBalances() public {
        assert(
            liquidityProviders.utilizedCAssetBalances(
                address(cDAI),
                address(this)
            ) == 0
        );
    }

    function testGetAssetsIn() public {
        address[] memory assetsIn = liquidityProviders.getAssetsIn(
            address(this)
        );
    }

    function testSetCAssetAddress() public {
        liquidityProviders.setCAssetAddress(address(0), address(1));
    }

    function testSupplyErc20() public {
        liquidityProviders.supplyErc20(address(DAI), 10000 ether);
    }

    function testSupplyCErc20() public {
        liquidityProviders.supplyCErc20(address(cDAI), 10000000);
    }

    function testWithdrawErc20True() public {
        liquidityProviders.withdrawErc20(address(DAI), true, 10000000);
    }

    function testWithdrawErc20False() public {
        liquidityProviders.withdrawErc20(address(DAI), false, 1 ether);
    }

    function testWithdrawCErc20() public {
        liquidityProviders.withdrawCErc20(address(cDAI), 10000000);
    }

    function testSupplyEth() public {
        liquidityProviders.supplyEth{value: 10 ether}();
    }

    // This fail case test fails because the 18 decimal value is greater than the cETH balance
    function testFailSupplyCEth() public {
        liquidityProviders.supplyCEth(1 ether);
    }

    function testWithdrawEthTrue() public {
        liquidityProviders.withdrawEth(true, 10000000);
    }

    function testWithdrawEthFalse() public {
        liquidityProviders.withdrawEth(false, 1 ether);
    }

    function testWithdrawCEth() public {
        liquidityProviders.withdrawCEth(10000000);
    }
}
