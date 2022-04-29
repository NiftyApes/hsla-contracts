// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import "../../interfaces/compound/ICERC20.sol";
import "../../interfaces/compound/ICEther.sol";
import "../../NiftyApes.sol";
import "../../interfaces/niftyapes/admin/INiftyApesAdminEvents.sol";
import "../../interfaces/niftyapes/liquidity/ILiquidityEvents.sol";

import "../common/BaseTest.sol";
import "../mock/CERC20Mock.sol";
import "../mock/CEtherMock.sol";
import "../mock/ERC20Mock.sol";

contract LiquidityProvidersUnitTest is BaseTest, ILiquidityEvents, INiftyApesAdminEvents {
    NiftyApes liquidityProviders;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    CEtherMock cEtherToken;

    bool acceptEth;

    receive() external payable {
        require(acceptEth, "acceptEth");
    }

    function setUp() public {
        liquidityProviders = new NiftyApes();
        liquidityProviders.initialize();

        usdcToken = new ERC20Mock();
        usdcToken.initialize("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock();
        cUSDCToken.initialize(usdcToken);
        liquidityProviders.setCAssetAddress(address(usdcToken), address(cUSDCToken));

        cEtherToken = new CEtherMock();
        cEtherToken.initialize();

        acceptEth = true;
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

    function testCannotSupplyErc20_asset_not_whitelisted() public {
        hevm.expectRevert("asset allow list");
        liquidityProviders.supplyErc20(address(0x0000000000000000000000000000000000000001), 1);
    }

    function testSupplyErc20_supply_erc20() public {
        assertEq(usdcToken.balanceOf(address(this)), 0);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        uint256 cTokensMinted = liquidityProviders.supplyErc20(address(usdcToken), 1);
        assertEq(cTokensMinted, 1 ether);

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 1 ether);
        assertEq(usdcToken.balanceOf(address(this)), 0);
        assertEq(cUSDCToken.balanceOf(address(this)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 1 ether);
    }

    function testCannotSupplyErc20_maxCAssethit() public {
        usdcToken.mint(address(this), 2);
        usdcToken.approve(address(liquidityProviders), 2);

        liquidityProviders.setMaxCAssetBalance(address(usdcToken), 1 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.expectRevert("max casset");

        liquidityProviders.supplyErc20(address(usdcToken), 1);
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

        uint256 cTokensMinted = liquidityProviders.supplyErc20(address(usdcToken), 1);
        assertEq(cTokensMinted, 0.5 ether);

        assertEq(
            liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)),
            0.5 ether
        );

        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0.5 ether);
    }

    function testCannotSupplyErc20_mint_fails() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);

        cUSDCToken.setMintFail(true);

        hevm.expectRevert("cToken mint");

        liquidityProviders.supplyErc20(address(usdcToken), 1);
    }

    function testCannotSupplyCErc20_asset_not_whitelisted() public {
        hevm.expectRevert("cAsset allow list");
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

    function testSupplyCErc20_supply_cerc20_with_event() public {
        usdcToken.mint(address(this), 1);

        cUSDCToken.mint(1);
        cUSDCToken.approve(address(liquidityProviders), 1);

        hevm.expectEmit(true, false, false, true);

        emit CErc20Supplied(address(this), address(cUSDCToken), 1);

        liquidityProviders.supplyCErc20(address(cUSDCToken), 1);
    }

    function testCannotSupplyCErc20_maxCAssethit() public {
        usdcToken.mint(address(this), 2);

        cUSDCToken.mint(2);
        cUSDCToken.approve(address(liquidityProviders), 2 ether);

        liquidityProviders.setMaxCAssetBalance(address(usdcToken), 1 ether);

        liquidityProviders.supplyCErc20(address(cUSDCToken), 1 ether);

        hevm.expectRevert("max casset");

        liquidityProviders.supplyCErc20(address(cUSDCToken), 1 ether);
    }

    function testCannotSupplyCErc20_transfer_from_fails() public {
        usdcToken.mint(address(this), 1);

        cUSDCToken.mint(1);
        cUSDCToken.approve(address(liquidityProviders), 1);

        cUSDCToken.setTransferFromFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        liquidityProviders.supplyCErc20(address(cUSDCToken), 1);
    }

    function testCannotWithdrawErc20_asset_not_whitelisted() public {
        hevm.expectRevert("asset allow list");
        liquidityProviders.withdrawErc20(address(0x0000000000000000000000000000000000000001), 1);
    }

    function testWithdrawErc20_works() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        uint256 cTokensBurnt = liquidityProviders.withdrawErc20(address(usdcToken), 1);
        assertEq(cTokensBurnt, 1 ether);

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(usdcToken.balanceOf(address(this)), 1);
    }

    function testWithdrawErc20_works_event() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.expectEmit(true, false, false, true);

        emit Erc20Withdrawn(address(this), address(usdcToken), 1, 1 ether);

        liquidityProviders.withdrawErc20(address(usdcToken), 1);
    }

    function testCannotWithdrawErc20_redeemUnderlyingFails() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        cUSDCToken.setRedeemUnderlyingFail(true);

        hevm.expectRevert("redeemUnderlying failed");

        liquidityProviders.withdrawErc20(address(usdcToken), 1);
    }

    function testCannotWithdrawErc20_withdraw_more_than_account_has() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        // deposit some funds from a different address
        hevm.startPrank(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000001)
        );

        usdcToken.mint(address(0x0000000000000000000000000000000000000001), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.stopPrank();

        hevm.expectRevert("Insufficient cToken balance");

        liquidityProviders.withdrawErc20(address(usdcToken), 2);
    }

    function testCannotWithdrawErc20_underlying_transfer_fails() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        usdcToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        liquidityProviders.withdrawErc20(address(usdcToken), 1);
    }

    function testCannotWithdrawCErc20_asset_not_whitelisted() public {
        hevm.expectRevert("cAsset allow list");
        liquidityProviders.withdrawCErc20(address(0x0000000000000000000000000000000000000001), 1);
    }

    function testWithdrawCErc20_works() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        liquidityProviders.withdrawCErc20(address(cUSDCToken), 1 ether);

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(cUSDCToken.balanceOf(address(this)), 1 ether);
    }

    function testWithdrawCErc20_works_event() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.expectEmit(true, false, false, true);

        emit CErc20Withdrawn(address(this), address(cUSDCToken), 1 ether);

        liquidityProviders.withdrawCErc20(address(cUSDCToken), 1 ether);
    }

    function testCannotWithdrawCErc20_withdraw_more_than_account_has() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        // deposit some funds from a different address
        hevm.startPrank(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000001)
        );

        usdcToken.mint(address(0x0000000000000000000000000000000000000001), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.stopPrank();

        hevm.expectRevert("Insufficient cToken balance");

        liquidityProviders.withdrawCErc20(address(cUSDCToken), 2 ether);
    }

    function testCannotWithdrawCErc20_transfer_fails() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        cUSDCToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        liquidityProviders.withdrawCErc20(address(cUSDCToken), 1 ether);
    }

    function testCannotSupplyEth_asset_not_whitelisted() public {
        hevm.expectRevert("asset allow list");
        liquidityProviders.supplyEth{ value: 1 }();
    }

    function testSupplyEth20_supply_eth() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        uint256 startingBalance = address(this).balance;
        assertEq(cEtherToken.balanceOf(address(this)), 0);

        assertEq(cEtherToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(address(liquidityProviders).balance, 0);

        uint256 cTokensMinted = liquidityProviders.supplyEth{ value: 1 }();
        assertEq(cTokensMinted, 1 ether);

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cEtherToken)), 1 ether);
        assertEq(address(this).balance, startingBalance - 1);
        assertEq(cEtherToken.balanceOf(address(this)), 0);

        assertEq(address(cEtherToken).balance, 1);
        assertEq(cEtherToken.balanceOf(address(liquidityProviders)), 1 ether);
    }

    function testSupplyEth20_with_event() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        hevm.expectEmit(true, false, false, true);

        emit EthSupplied(address(this), 1, 1 ether);

        liquidityProviders.supplyEth{ value: 1 }();
    }

    function testCannotSupplyEth_maxCAssethit() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        liquidityProviders.setMaxCAssetBalance(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            1 ether
        );

        liquidityProviders.supplyEth{ value: 1 }();

        hevm.expectRevert("max casset");

        liquidityProviders.supplyEth{ value: 1 }();
    }

    function testSupplyEth20_different_exchange_rate() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        cEtherToken.setExchangeRateCurrent(2);

        uint256 cTokensMinted = liquidityProviders.supplyEth{ value: 1 }();
        assertEq(cTokensMinted, 0.5 ether);

        assertEq(
            liquidityProviders.getCAssetBalance(address(this), address(cEtherToken)),
            0.5 ether
        );

        assertEq(cEtherToken.balanceOf(address(liquidityProviders)), 0.5 ether);
    }

    function testCannotSupplyEth_mint_fails() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        cEtherToken.setMintFail(true);

        hevm.expectRevert("cToken mint");

        liquidityProviders.supplyEth{ value: 1 }();
    }

    function testCannotWithdrawEth_asset_not_whitelisted() public {
        hevm.expectRevert("asset allow list");
        liquidityProviders.withdrawEth(1);
    }

    function testWithdrawEth_works() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        uint256 startingBalance = address(this).balance;

        liquidityProviders.supplyEth{ value: 1 }();

        uint256 cTokensBurnt = liquidityProviders.withdrawEth(1);
        assertEq(cTokensBurnt, 1 ether);

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cEtherToken)), 0);

        assertEq(address(liquidityProviders).balance, 0);
        assertEq(cEtherToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(address(this).balance, startingBalance);
    }

    function testWithdrawEth_works_event() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.supplyEth{ value: 1 }();

        hevm.expectEmit(true, false, false, true);

        emit EthWithdrawn(address(this), 1, 1 ether);

        liquidityProviders.withdrawEth(1);
    }

    function testCannotWithdrawEth_redeemUnderlyingFails() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.supplyEth{ value: 1 }();

        cEtherToken.setRedeemUnderlyingFail(true);

        hevm.expectRevert("redeemUnderlying failed");

        liquidityProviders.withdrawEth(1);
    }

    function testCannotWithdrawEth_withdraw_more_than_account_has() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        liquidityProviders.supplyEth{ value: 1 }();

        // deposit some funds from a different address
        hevm.startPrank(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000001)
        );

        liquidityProviders.supplyEth{ value: 1 }();

        hevm.stopPrank();

        hevm.expectRevert("Insufficient cToken balance");

        liquidityProviders.withdrawEth(2);
    }

    function testCannotWithdrawEth_underlying_transfer_fails() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        liquidityProviders.supplyEth{ value: 1 }();

        acceptEth = false;

        hevm.expectRevert("Address: unable to send value, recipient may have reverted");

        liquidityProviders.withdrawEth(1);
    }

    // TODO(dankurka): Missing unit tests for max c asset balance
}
