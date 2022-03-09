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

    LiquidityProviders liquidityProviders;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    function setUp() public {
        liquidityProviders = new LiquidityProviders();

        usdcToken = new ERC20Mock("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock(usdcToken);
    }

    function testSetCAddressMapping_returns_null_address() public {
        assertEq(
            liquidityProviders.assetToCAsset(address(0x0000000000000000000000000000000000000001)),
            address(0x0000000000000000000000000000000000000000)
        );
    }

    function testSetCAddressMapping_can_be_set_by_owner() public {
        hevm.expectEmit(true, false, false, false);

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
}
