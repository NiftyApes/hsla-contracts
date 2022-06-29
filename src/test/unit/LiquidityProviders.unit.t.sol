// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20Upgradeable.sol";
import "../../interfaces/compound/ICERC20.sol";
import "../../interfaces/compound/ICEther.sol";
import "../../Lending.sol";
import "../../Liquidity.sol";
import "../../interfaces/niftyapes/liquidity/ILiquidityEvents.sol";

import "../common/BaseTest.sol";
import "../mock/CERC20Mock.sol";
import "../mock/CEtherMock.sol";
import "../mock/ERC20Mock.sol";

contract LiquidityProvidersUnitTest is BaseTest, ILiquidityEvents {
    NiftyApesLiquidity liquidityProviders;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;
    CEtherMock cEtherToken;
    address compContractAddress = 0xbbEB7c67fa3cfb40069D19E598713239497A3CA5;

    bool acceptEth;

    address constant NOT_ADMIN = address(0x5050);
    address constant SANCTIONED_ADDRESS = address(0x7FF9cFad3877F21d41Da833E2F775dB0569eE3D9);

    receive() external payable {
        require(acceptEth, "acceptEth");
    }

    function setUp() public {
        liquidityProviders = new NiftyApesLiquidity();
        liquidityProviders.initialize(compContractAddress);

        usdcToken = new ERC20Mock();
        usdcToken.initialize("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock();
        cUSDCToken.initialize(usdcToken);
        liquidityProviders.setCAssetAddress(address(usdcToken), address(cUSDCToken));
        liquidityProviders.setMaxCAssetBalance(address(cUSDCToken), 2**256 - 1);

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
        hevm.expectRevert("00040");
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

    function testCannotSupplyErc20_maxCAsset_hit() public {
        usdcToken.mint(address(this), 2);
        usdcToken.approve(address(liquidityProviders), 2);

        liquidityProviders.setMaxCAssetBalance(address(cUSDCToken), 1 ether);

        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.expectRevert("00044");

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

        hevm.expectRevert("00037");

        liquidityProviders.supplyErc20(address(usdcToken), 1);
    }

    function testCannotSupplyErc20_if_sanctioned() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);

        hevm.expectRevert("00017");

        hevm.startPrank(SANCTIONED_ADDRESS);

        liquidityProviders.supplyErc20(address(usdcToken), 1);
    }

    function testCannotSupplyCErc20_asset_not_whitelisted() public {
        hevm.expectRevert("00041");
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

    function testCannotSupplyCErc20_maxCAsset_hit() public {
        usdcToken.mint(address(this), 2);

        cUSDCToken.mint(2);
        cUSDCToken.approve(address(liquidityProviders), 2 ether);

        liquidityProviders.setMaxCAssetBalance(address(cUSDCToken), 1 ether);

        liquidityProviders.supplyCErc20(address(cUSDCToken), 1 ether);

        hevm.expectRevert("00044");

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

    function testCannotSupplyCErc20_if_sanctioned() public {
        usdcToken.mint(address(this), 1);

        cUSDCToken.mint(1);
        cUSDCToken.approve(address(liquidityProviders), 1);

        hevm.expectRevert("00017");

        hevm.startPrank(SANCTIONED_ADDRESS);

        liquidityProviders.supplyCErc20(address(cUSDCToken), 1);
    }

    function testCannotWithdrawErc20_asset_not_whitelisted() public {
        hevm.expectRevert("00040");
        liquidityProviders.withdrawErc20(address(0x0000000000000000000000000000000000000001), 1);
    }

    function testWithdrawErc20_works() public {
        hevm.startPrank(NOT_ADMIN);
        usdcToken.mint(NOT_ADMIN, 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        uint256 cTokensBurnt = liquidityProviders.withdrawErc20(address(usdcToken), 1);
        assertEq(cTokensBurnt, 1 ether);

        assertEq(liquidityProviders.getCAssetBalance(NOT_ADMIN, address(cUSDCToken)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(usdcToken.balanceOf(NOT_ADMIN), 1);
    }

    function testWithdrawErc20_works_owner() public {
        usdcToken.mint(address(this), 100);
        usdcToken.approve(address(liquidityProviders), 100);
        liquidityProviders.supplyErc20(address(usdcToken), 100);

        uint256 cTokensBurnt = liquidityProviders.withdrawErc20(address(usdcToken), 99);
        assertEq(cTokensBurnt, 100 ether);

        assertEq(liquidityProviders.getCAssetBalance(address(this), address(cUSDCToken)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(usdcToken.balanceOf(address(this)), 99);
    }

    function testWithdrawErc20_works_event() public {
        hevm.startPrank(NOT_ADMIN);
        usdcToken.mint(NOT_ADMIN, 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.expectEmit(true, false, false, true);

        emit Erc20Withdrawn(NOT_ADMIN, address(usdcToken), 1, 1 ether);

        liquidityProviders.withdrawErc20(address(usdcToken), 1);
    }

    function testCannotWithdrawErc20_redeemUnderlyingFails() public {
        hevm.startPrank(NOT_ADMIN);
        usdcToken.mint(NOT_ADMIN, 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        cUSDCToken.setRedeemUnderlyingFail(true);

        hevm.expectRevert("00038");

        liquidityProviders.withdrawErc20(address(usdcToken), 1);
    }

    function testCannotWithdrawErc20_withdraw_more_than_account_has() public {
        hevm.startPrank(NOT_ADMIN);
        usdcToken.mint(NOT_ADMIN, 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);
        hevm.stopPrank();

        // deposit some funds from a different address
        hevm.startPrank(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000001)
        );

        usdcToken.mint(address(0x0000000000000000000000000000000000000001), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.stopPrank();

        hevm.startPrank(NOT_ADMIN);
        hevm.expectRevert("00034");

        liquidityProviders.withdrawErc20(address(usdcToken), 2);
        hevm.stopPrank();
    }

    function testCannotWithdrawErc20_underlying_transfer_fails() public {
        hevm.startPrank(NOT_ADMIN);
        usdcToken.mint(NOT_ADMIN, 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        usdcToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        liquidityProviders.withdrawErc20(address(usdcToken), 1);
    }

    function testCannotWithdrawCErc20_no_asset_balance() public {
        hevm.expectRevert("00045");
        liquidityProviders.withdrawCErc20(address(0x0000000000000000000000000000000000000001), 1);
    }

    function testWithdrawCErc20_works() public {
        hevm.startPrank(NOT_ADMIN);
        usdcToken.mint(NOT_ADMIN, 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        liquidityProviders.withdrawCErc20(address(cUSDCToken), 1 ether);

        assertEq(liquidityProviders.getCAssetBalance(NOT_ADMIN, address(cUSDCToken)), 0);

        assertEq(usdcToken.balanceOf(address(liquidityProviders)), 0);
        assertEq(cUSDCToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(cUSDCToken.balanceOf(NOT_ADMIN), 1 ether);
    }

    function testWithdrawCErc20_works_event() public {
        hevm.startPrank(NOT_ADMIN);
        usdcToken.mint(NOT_ADMIN, 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.expectEmit(true, false, false, true);

        emit CErc20Withdrawn(NOT_ADMIN, address(cUSDCToken), 1 ether);

        liquidityProviders.withdrawCErc20(address(cUSDCToken), 1 ether);
    }

    function testCannotWithdrawCErc20_withdraw_more_than_account_has() public {
        hevm.startPrank(NOT_ADMIN);
        usdcToken.mint(NOT_ADMIN, 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);
        hevm.stopPrank();

        // deposit some funds from a different address
        hevm.startPrank(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000001)
        );

        usdcToken.mint(address(0x0000000000000000000000000000000000000001), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.expectRevert("00034");

        liquidityProviders.withdrawCErc20(address(cUSDCToken), 2 ether);
    }

    function testCannotWithdrawCErc20_transfer_fails() public {
        hevm.startPrank(NOT_ADMIN);
        usdcToken.mint(NOT_ADMIN, 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        cUSDCToken.setTransferFail(true);

        hevm.expectRevert("SafeERC20: ERC20 operation did not succeed");

        liquidityProviders.withdrawCErc20(address(cUSDCToken), 1 ether);
    }

    function testCannotSupplyEth_asset_not_whitelisted() public {
        hevm.expectRevert("00040");
        liquidityProviders.supplyEth{ value: 1 }();
    }

    function testSupplyEth_supply_eth() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 2**256 - 1);

        hevm.deal(address(liquidityProviders), 0);

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

    function testSupplyEth_with_event() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 2**256 - 1);

        hevm.expectEmit(true, false, false, true);

        emit EthSupplied(address(this), 1, 1 ether);

        liquidityProviders.supplyEth{ value: 1 }();
    }

    function testCannotSupplyEth_maxCAsset_hit() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 1 ether);

        liquidityProviders.supplyEth{ value: 1 }();

        hevm.expectRevert("00044");

        liquidityProviders.supplyEth{ value: 1 }();
    }

    function testSupplyEth_different_exchange_rate() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 2**256 - 1);

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
        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 2**256 - 1);

        cEtherToken.setMintFail(true);

        hevm.expectRevert("cToken mint");

        liquidityProviders.supplyEth{ value: 1 }();
    }

    function testCannotSupplyEth_if_sanctioned() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 2**256 - 1);

        hevm.expectRevert("00017");

        hevm.deal(SANCTIONED_ADDRESS, 1);

        hevm.startPrank(SANCTIONED_ADDRESS);

        liquidityProviders.supplyEth{ value: 1 }();
    }

    function testCannotWithdrawEth_asset_not_whitelisted() public {
        hevm.expectRevert("00040");
        liquidityProviders.withdrawEth(1);
    }

    function testWithdrawEth_works() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 2**256 - 1);

        hevm.startPrank(NOT_ADMIN);

        hevm.deal(address(liquidityProviders), 0);
        hevm.deal(address(NOT_ADMIN), 1);

        uint256 startingBalance = NOT_ADMIN.balance;

        liquidityProviders.supplyEth{ value: 1 }();

        uint256 cTokensBurnt = liquidityProviders.withdrawEth(1);
        assertEq(cTokensBurnt, 1 ether);

        assertEq(liquidityProviders.getCAssetBalance(NOT_ADMIN, address(cEtherToken)), 0);

        assertEq(address(liquidityProviders).balance, 0);
        assertEq(cEtherToken.balanceOf(address(liquidityProviders)), 0);

        assertEq(NOT_ADMIN.balance, startingBalance);
    }

    function testWithdrawEth_works_event() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 2**256 - 1);

        hevm.startPrank(NOT_ADMIN);
        hevm.deal(address(NOT_ADMIN), 1);

        liquidityProviders.supplyEth{ value: 1 }();

        hevm.expectEmit(true, false, false, true);

        emit EthWithdrawn(NOT_ADMIN, 1, 1 ether);

        liquidityProviders.withdrawEth(1);
    }

    function testCannotWithdrawEth_redeemUnderlyingFails() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 2**256 - 1);

        hevm.startPrank(NOT_ADMIN);
        hevm.deal(address(NOT_ADMIN), 1);

        liquidityProviders.supplyEth{ value: 1 }();

        cEtherToken.setRedeemUnderlyingFail(true);

        hevm.expectRevert("00038");

        liquidityProviders.withdrawEth(1);
    }

    function testCannotWithdrawEth_withdraw_more_than_account_has() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 2**256 - 1);

        hevm.startPrank(NOT_ADMIN);
        hevm.deal(address(NOT_ADMIN), 1);

        liquidityProviders.supplyEth{ value: 1 }();

        hevm.stopPrank();

        // deposit some funds from a different address
        hevm.startPrank(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000001)
        );

        liquidityProviders.supplyEth{ value: 1 }();

        hevm.expectRevert("00034");

        liquidityProviders.withdrawEth(2);
    }

    // this test was throwing on 'amount 0' error due to owner() withdrawl
    // contract owner should be updated and propogated through other tests
    function testCannotWithdrawEth_underlying_transfer_fails() public {
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );
        liquidityProviders.setMaxCAssetBalance(address(cEtherToken), 2**256 - 1);

        hevm.deal(address(this), 2);

        liquidityProviders.supplyEth{ value: 1 }();

        acceptEth = false;

        // hevm.expectRevert("Address: unable to send value, recipient may have reverted");
        hevm.expectRevert("00045");

        liquidityProviders.withdrawEth(1);
    }

    function testWithdrawEth_regen_collective_event_emits_when_owner() public {
        usdcToken.mint(address(this), 1);
        usdcToken.approve(address(liquidityProviders), 1);
        liquidityProviders.supplyErc20(address(usdcToken), 1);

        hevm.startPrank(liquidityProviders.owner());
        usdcToken.mint(liquidityProviders.owner(), 100);
        usdcToken.approve(address(liquidityProviders), 100);
        liquidityProviders.supplyErc20(address(usdcToken), 100);
        hevm.stopPrank();

        hevm.warp(block.timestamp + 1 weeks);

        hevm.expectEmit(true, true, true, true);

        emit PercentForRegen(
            liquidityProviders.regenCollectiveAddress(),
            address(usdcToken),
            1,
            1010000000000000000
        );

        hevm.startPrank(liquidityProviders.owner());

        liquidityProviders.withdrawErc20(address(usdcToken), 100);
    }

    function testCAssetAmountToAssetAmount() public {
        cUSDCToken.setExchangeRateCurrent(220154645140434444389595003); // exchange rate of DAI at time of edit

        uint256 result = liquidityProviders.cAssetAmountToAssetAmount(address(cUSDCToken), 1e8); // supply 1 mockCUSDC, would be better to call this mock DAI as USDC has 6 decimals

        assertEq(result, 22015464514043444); // ~ 0.02 DAI
    }

    // TODO(miller): Missing unit tests for max c asset balance
}
