// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "./console.sol";
import "ds-test/test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/compound/ICERC20.sol";
import "../interfaces/compound/ICEther.sol";
import "../LiquidityProviders.sol";

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

contract LiquidityProvidersTest is DSTest, Utility {
    Ievm IEVM;
    IUniswapV2Router SushiSwapRouter;
    IWETH WETH;
    IERC20 DAI;
    ICERC20 cDAI;
    ICEther cETH;
    LiquidityProviders liquidityProviders;

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
        liquidityProviders.setCAssetAddress(address(IEVM), address(1));
    }

    function testSupplyErc20() public {
        liquidityProviders.supplyErc20(address(DAI), 10000 ether);
    }

    // TODO(It seems like these failures are likely around inconsistent input for asset/cAsset and)
    // related initialization of the asset => cAsset mapping
    // supplyCErc20 must accept the underlying erc20 because we cannot allow users to input any arbitrary cErc20 address

    function testSupplyCErc20() public {
        liquidityProviders.supplyCErc20(address(DAI), 10000000);
    }

    function testWithdrawErc20True() public {
        liquidityProviders.withdrawErc20(address(DAI), true, 10000000);
    }

    function testWithdrawErc20False() public {
        liquidityProviders.withdrawErc20(address(DAI), false, 1 ether);
    }

    function testWithdrawCErc20() public {
        liquidityProviders.withdrawCErc20(address(DAI), 10000000);
    }

    function testSupplyEth() public {
        liquidityProviders.supplyEth{value: 10 ether}();
    }

    // how does this test for a fail case?
    function testFailSupplyCEth() public {
        liquidityProviders.supplyCEth(1 ether);
    }

    function testWithdrawEth1(uint x) public {
        liquidityProviders.withdrawEth(true, x);
    }

    function testWithdrawEth2(uint x) public {
        liquidityProviders.withdrawEth(false, x);
    }

    function testWithdrawCEth() public {
        liquidityProviders.withdrawCEth(10000000);
    }

    //function test
}
