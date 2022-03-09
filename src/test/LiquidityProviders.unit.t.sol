// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./Console.sol";
import "ds-test/test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/compound/ICERC20.sol";
import "../interfaces/compound/ICEther.sol";
import "../LiquidityProviders.sol";
import "../Exponential.sol";
import "./Utilities.sol";

import "./mock/CERC20Mock.sol";
import "./mock/ERC20Mock.sol";

// @dev These tests are intended to be run against a forked mainnet.

contract LiquidityProvidersUnitTest is DSTest, TestUtility, Exponential {
    // TODO(dankurka): Remove
    event NewAssetWhitelisted(address asset, address cAsset);
    event Erc20Supplied(
        address indexed depositor,
        address indexed asset,
        uint256 tokenAmount,
        uint256 cTokenAmount
    );

    LiquidityProviders liquidityProviders;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    function setUp() public {
        liquidityProviders = new LiquidityProviders();

        usdcToken = new ERC20Mock("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock(usdcToken);

        liquidityProviders.setCAssetAddress(address(usdcToken), address(cUSDCToken));
    }

    function testSetCAddressMapping_returns_null_address() public {
        assertEq(
            liquidityProviders.assetToCAsset(address(0x0000000000000000000000000000000000000001)),
            address(0x0000000000000000000000000000000000000000)
        );
    }

    function testSetCAddressMapping_can_be_set_by_owner() public {
        hevm.expectEmit(true, false, false, true);

        emit NewAssetWhitelisted(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000002)
        );

        liquidityProviders.setCAssetAddress(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000002)
        );

        assertEq(
            liquidityProviders.assetToCAsset(address(0x0000000000000000000000000000000000000001)),
            address(0x0000000000000000000000000000000000000002)
        );
    }

    function testFailSetCAddressMapping_can_not_be_set_by_non_owner() public {
        liquidityProviders.renounceOwnership();

        liquidityProviders.setCAssetAddress(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000002)
        );
    }

    function testFailSetCAddressMapping_can_not_overwrite_mapping_asset() public {
        liquidityProviders.setCAssetAddress(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000002)
        );

        liquidityProviders.setCAssetAddress(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000003)
        );
    }

    function testFailSetCAddressMapping_can_not_overwrite_mapping_casset() public {
        liquidityProviders.setCAssetAddress(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000002)
        );

        liquidityProviders.setCAssetAddress(
            address(0x0000000000000000000000000000000000000003),
            address(0x0000000000000000000000000000000000000002)
        );
    }

    function testCAssetBalance_starts_at_zero() public {
        assertEq(
            liquidityProviders.getCAssetBalance(
                address(0x0000000000000000000000000000000000000001),
                address(0x0000000000000000000000000000000000000002)
            ),
            0
        );
    }

    function testFailSupplyErc20_asset_not_whitelisted() public {
        liquidityProviders.supplyErc20(address(0x0000000000000000000000000000000000000001), 1);
    }

    function testSupplyErc20_supply_erc20() public {
        assertEq(usdcToken.balanceOf(address(this)), 0);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        liquidityProviders.supplyErc20(address(usdcToken), 1);

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 1 ether);
        assertEq(usdcToken.balanceOf(address(this)), 0);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 1 ether);
    }

    function testSupplyErc20_supply_erc20_with_event() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);

        hevm.expectEmit(true, false, false, true);

        emit Erc20Supplied(address(this), address(usdcToken), 1, 1 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 1);
    }

    function testSupplyErc20_supply_erc20_different_exchange_rate() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);

        cUSDCToken.setExchangeRateCurrent(2);

        liquidityProviders.supplyErc20(address(usdcToken), 1);

        assertEq(
            liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)),
            0.5 ether
        );

        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0.5 ether);
    }

    function testFailSupplyErc20_mint_fails() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);

        cUSDCToken.setMintFail(true);

        liquidityProviders.supplyErc20(address(usdcToken), 1);
    }

    function testFailSupplyCErc20_asset_not_whitelisted() public {
        liquidityProviders.supplyCErc20(address(0x0000000000000000000000000000000000000001), 1);
    }

    function testSupplyCErc20_supply_cerc20() public {
        usdcToken.mint(address(this), 1);

        cUSDCToken.mint(1);
        cUSDCToken.approve(address(liquidityProviders), 1);

        liquidityProviders.supplyCErc20(address(cUSDCToken), 1);

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 1);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 1);
    }
}
