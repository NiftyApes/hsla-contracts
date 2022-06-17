// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20Upgradeable.sol";
import "../../interfaces/compound/ICERC20.sol";
import "../../interfaces/compound/ICEther.sol";
import "../../Lending.sol";
import "../../Liquidity.sol";
import "../../Offers.sol";
import "../../SigLending.sol";
import "../../interfaces/niftyapes/lending/ILendingEvents.sol";
import "../../interfaces/niftyapes/liquidity/ILiquidityEvents.sol";
import "../common/BaseTest.sol";
import "../mock/CERC20Mock.sol";
import "../mock/CEtherMock.sol";
import "../mock/ERC20Mock.sol";

contract AdminUnitTest is BaseTest, ILendingEvents, ILiquidityEvents {
    NiftyApesLending niftyApes;
    NiftyApesOffers offersContract;
    NiftyApesLiquidity liquidityProviders;
    NiftyApesSigLending sigLendingAuction;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    CEtherMock cEtherToken;

    bool acceptEth;

    address constant NOT_ADMIN = address(0x5050);

    receive() external payable {
        require(acceptEth, "acceptEth");
    }

    function setUp() public {
        liquidityProviders = new NiftyApesLiquidity();
        liquidityProviders.initialize();

        offersContract = new NiftyApesOffers();
        offersContract.initialize(address(liquidityProviders));

        sigLendingAuction = new NiftyApesSigLending();
        sigLendingAuction.initialize(address(offersContract));

        niftyApes = new NiftyApesLending();
        niftyApes.initialize(
            address(liquidityProviders),
            address(offersContract),
            address(sigLendingAuction)
        );

        usdcToken = new ERC20Mock();
        usdcToken.initialize("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock();
        cUSDCToken.initialize(usdcToken);
        liquidityProviders.setCAssetAddress(address(usdcToken), address(cUSDCToken));

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
        hevm.expectEmit(true, false, false, true);

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

    function testUpdateProtocolInterestBps_owner() public {
        assertEq(niftyApes.protocolInterestBps(), 0);
        hevm.expectEmit(true, false, false, true);

        emit ProtocolInterestBpsUpdated(0, 1);
        niftyApes.updateProtocolInterestBps(1);
        assertEq(niftyApes.protocolInterestBps(), 1);
    }

    function testCannotUpdateRefinancePremiumLenderFee_not_owner() public {
        hevm.startPrank(NOT_ADMIN);
        hevm.expectRevert("Ownable: caller is not the owner");
        niftyApes.updateOriginationPremiumLenderBps(1);
    }

    function testCannotUpdateRefinancePremiumLenderFee_max_fee() public {
        hevm.expectRevert("00002");
        niftyApes.updateOriginationPremiumLenderBps(1001);
    }

    function testUpdateRefinancePremiumLenderFee_owner() public {
        assertEq(niftyApes.originationPremiumBps(), 50);
        hevm.expectEmit(true, false, false, true);

        emit OriginationPremiumBpsUpdated(50, 1);
        niftyApes.updateOriginationPremiumLenderBps(1);
        assertEq(niftyApes.originationPremiumBps(), 1);
    }

    function testCannotUpdateRefinancePremiumProtocolFee_not_owner() public {
        hevm.startPrank(NOT_ADMIN);
        hevm.expectRevert("Ownable: caller is not the owner");
        niftyApes.updateGasGriefingPremiumBps(1);
    }

    function testCannotUpdateRefinancePremiumProtocolFee_max_fee() public {
        hevm.expectRevert("00002");
        niftyApes.updateGasGriefingPremiumBps(1001);
    }

    function testUpdateRefinancePremiumProtocolFee_owner() public {
        assertEq(niftyApes.gasGriefingPremiumBps(), 25);
        hevm.expectEmit(true, false, false, true);

        emit GasGriefingPremiumBpsUpdated(25, 1);
        niftyApes.updateGasGriefingPremiumBps(1);
        assertEq(niftyApes.gasGriefingPremiumBps(), 1);
    }
}
