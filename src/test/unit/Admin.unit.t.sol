// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20Upgradeable.sol";
import "../../interfaces/compound/ICERC20.sol";
import "../../interfaces/compound/ICEther.sol";
import "../../Lending.sol";
import "../../Liquidity.sol";
import "../../Offers.sol";
import "../../SigLending.sol";
import "../../purchaseWithFinancing/PurchaseWithFinancing.sol";
import "../../interfaces/niftyapes/lending/ILendingEvents.sol";
import "../../interfaces/niftyapes/liquidity/ILiquidityEvents.sol";
import "../common/BaseTest.sol";
import "../mock/CERC20Mock.sol";
import "../mock/CEtherMock.sol";
import "../mock/ERC20Mock.sol";
import "../mock/SeaportMock.sol";
import "../mock/SudoswapFactoryMock.sol";
import "../mock/SudoswapRouterMock.sol";

contract AdminUnitTest is BaseTest, ILendingEvents, ILiquidityEvents {
    NiftyApesLending niftyApes;
    NiftyApesOffers offersContract;
    NiftyApesLiquidity liquidityProviders;
    NiftyApesSigLending sigLendingAuction;
    NiftyApesPurchaseWithFinancing purchaseWithFinancing;
    SeaportMock seaportMock;
    LSSVMPairFactoryMock sudoswapFactoryMock;
    LSSVMRouterMock sudoswapRouterMock;
    ERC20Mock daiToken;
    CERC20Mock cDAIToken;
    CEtherMock cEtherToken;
    address compContractAddress = 0xbbEB7c67fa3cfb40069D19E598713239497A3CA5;

    bool acceptEth;

    address constant NOT_ADMIN = address(0x5050);

    receive() external payable {
        require(acceptEth, "acceptEth");
    }

    function setUp() public {
        seaportMock = new SeaportMock();
        sudoswapFactoryMock = new LSSVMPairFactoryMock();
        sudoswapRouterMock = new LSSVMRouterMock();

        purchaseWithFinancing = new NiftyApesPurchaseWithFinancing();
        purchaseWithFinancing.initialize();

        liquidityProviders = new NiftyApesLiquidity();
        liquidityProviders.initialize(compContractAddress, address(purchaseWithFinancing));

        offersContract = new NiftyApesOffers();
        offersContract.initialize(address(liquidityProviders), address(purchaseWithFinancing));

        sigLendingAuction = new NiftyApesSigLending();
        sigLendingAuction.initialize(address(offersContract), address(purchaseWithFinancing));

        niftyApes = new NiftyApesLending();
        niftyApes.initialize(
            address(liquidityProviders),
            address(offersContract),
            address(sigLendingAuction),
            address(purchaseWithFinancing)
        );

        daiToken = new ERC20Mock();
        daiToken.initialize("USD Coin", "DAI");
        cDAIToken = new CERC20Mock();
        cDAIToken.initialize(daiToken);
        liquidityProviders.setCAssetAddress(address(daiToken), address(cDAIToken));

        cEtherToken = new CEtherMock();
        cEtherToken.initialize();

        acceptEth = true;
    }

    function testSetCAddressMapping_returns_null_address() public {
        assertEq(
            liquidityProviders.assetToCAsset(address(0x0000000000000000000000000000000000000001)),
            address(0x0000000000000000000000000000000000000000)
        );
    }

    function testSetCAddressMapping_can_be_set_by_owner() public {
        hevm.expectEmit(false, false, false, true);

        emit AssetToCAssetSet(
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

    function testCannotSetCAddressMapping_can_not_be_set_by_non_owner() public {
        hevm.startPrank(NOT_ADMIN);

        hevm.expectRevert("Ownable: caller is not the owner");
        liquidityProviders.setCAssetAddress(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000002)
        );
    }

    function testCannotUpdateProtocolInterestBps_not_owner() public {
        hevm.startPrank(NOT_ADMIN);
        hevm.expectRevert("Ownable: caller is not the owner");
        niftyApes.updateProtocolInterestBps(1);
    }

    function testCannotUpdateProtocolInterestBps_max_fee() public {
        hevm.expectRevert("00002");
        niftyApes.updateProtocolInterestBps(1001);
    }

    function testUpdateProtocolInterestBps_owner() public {
        assertEq(niftyApes.protocolInterestBps(), 0);
        hevm.expectEmit(false, false, false, true);

        emit ProtocolInterestBpsUpdated(0, 1);
        niftyApes.updateProtocolInterestBps(1);
        assertEq(niftyApes.protocolInterestBps(), 1);
    }

    function testCannotUpdateOriginationPremiumLenderBps_not_owner() public {
        hevm.startPrank(NOT_ADMIN);
        hevm.expectRevert("Ownable: caller is not the owner");
        niftyApes.updateOriginationPremiumLenderBps(1);
    }

    function testCannotUpdateOriginationPremiumLenderBps_max_fee() public {
        hevm.expectRevert("00002");
        niftyApes.updateOriginationPremiumLenderBps(1001);
    }

    function testUpdateOriginationPremiumLenderBps_owner() public {
        assertEq(niftyApes.originationPremiumBps(), 50);
        hevm.expectEmit(false, false, false, true);

        emit OriginationPremiumBpsUpdated(50, 1);
        niftyApes.updateOriginationPremiumLenderBps(1);
        assertEq(niftyApes.originationPremiumBps(), 1);
    }

    function testCannotUpdateGasGriefingPremiumBps_not_owner() public {
        hevm.startPrank(NOT_ADMIN);
        hevm.expectRevert("Ownable: caller is not the owner");
        niftyApes.updateGasGriefingPremiumBps(1);
    }

    function testCannotUpdateGasGriefingPremiumBps_max_fee() public {
        hevm.expectRevert("00002");
        niftyApes.updateGasGriefingPremiumBps(1001);
    }

    function testUpdateGasGriefingPremiumBps_owner() public {
        assertEq(niftyApes.gasGriefingPremiumBps(), 25);
        hevm.expectEmit(false, false, false, true);

        emit GasGriefingPremiumBpsUpdated(25, 1);
        niftyApes.updateGasGriefingPremiumBps(1);
        assertEq(niftyApes.gasGriefingPremiumBps(), 1);
    }

    function testCannotUpdateRegenCollectiveBpsOfRevenue_not_owner() public {
        hevm.startPrank(NOT_ADMIN);
        hevm.expectRevert("Ownable: caller is not the owner");
        liquidityProviders.updateRegenCollectiveBpsOfRevenue(1);
    }

    function testCannotUpdateRegenCollectiveBpsOfRevenue_max_fee() public {
        hevm.expectRevert("00002");
        liquidityProviders.updateRegenCollectiveBpsOfRevenue(1001);
    }

    function testCannotUpdateRegenCollectiveBpsOfRevenue_mustBeGreater() public {
        hevm.expectRevert("00039");
        liquidityProviders.updateRegenCollectiveBpsOfRevenue(1);
    }

    function testUpdateRegenCollectiveBpsOfRevenue_works() public {
        assertEq(liquidityProviders.regenCollectiveBpsOfRevenue(), 100);
        hevm.expectEmit(true, false, false, true);

        emit RegenCollectiveBpsOfRevenueUpdated(100, 101);
        liquidityProviders.updateRegenCollectiveBpsOfRevenue(101);
        assertEq(liquidityProviders.regenCollectiveBpsOfRevenue(), 101);
    }
}
