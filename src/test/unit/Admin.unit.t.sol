// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20Upgradeable.sol";
import "../../interfaces/compound/ICERC20.sol";
import "../../interfaces/compound/ICEther.sol";
import "../../Lending.sol";
import "../../interfaces/niftyapes/lending/ILendingEvents.sol";
import "../../interfaces/niftyapes/liquidity/ILiquidityEvents.sol";
import "../common/BaseTest.sol";
import "../mock/CERC20Mock.sol";
import "../mock/CEtherMock.sol";
import "../mock/ERC20Mock.sol";

contract AdminUnitTest is BaseTest, ILendingEvents, ILiquidityEvents {
    NiftyApesLending niftyApes;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    CEtherMock cEtherToken;

    bool acceptEth;

    address constant NOT_ADMIN = address(0x5050);

    receive() external payable {
        require(acceptEth, "acceptEth");
    }

    function setUp() public {
        niftyApes = new NiftyApesLending();
        niftyApes.initialize();

        usdcToken = new ERC20Mock();
        usdcToken.initialize("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock();
        cUSDCToken.initialize(usdcToken);
        niftyApes.setCAssetAddress(address(usdcToken), address(cUSDCToken));

        cEtherToken = new CEtherMock();
        cEtherToken.initialize();

        acceptEth = true;
    }

    function testSetCAddressMapping_returns_null_address() public {
        assertEq(
            niftyApes.assetToCAsset(address(0x0000000000000000000000000000000000000001)),
            address(0x0000000000000000000000000000000000000000)
        );
    }

    function testSetCAddressMapping_can_be_set_by_owner() public {
        hevm.expectEmit(true, false, false, true);

        emit NewAssetListed(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000002)
        );

        niftyApes.setCAssetAddress(
            address(0x0000000000000000000000000000000000000001),
            address(0x0000000000000000000000000000000000000002)
        );

        assertEq(
            niftyApes.assetToCAsset(address(0x0000000000000000000000000000000000000001)),
            address(0x0000000000000000000000000000000000000002)
        );
    }

    function testCannotSetCAddressMapping_can_not_be_set_by_non_owner() public {
        hevm.startPrank(NOT_ADMIN);

        hevm.expectRevert("Ownable: caller is not the owner");
        niftyApes.setCAssetAddress(
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
        niftyApes.updateRefinancePremiumLenderBps(1);
    }

    function testCannotUpdateRefinancePremiumLenderFee_max_fee() public {
        hevm.expectRevert("max fee");
        niftyApes.updateRefinancePremiumLenderBps(1001);
    }

    function testUpdateRefinancePremiumLenderFee_owner() public {
        assertEq(niftyApes.refinancePremiumLenderBps(), 50);
        hevm.expectEmit(true, false, false, true);

        emit RefinancePremiumLenderBpsUpdated(50, 1);
        niftyApes.updateRefinancePremiumLenderBps(1);
        assertEq(niftyApes.refinancePremiumLenderBps(), 1);
    }

    function testCannotUpdateRefinancePremiumProtocolFee_not_owner() public {
        hevm.startPrank(NOT_ADMIN);
        hevm.expectRevert("Ownable: caller is not the owner");
        niftyApes.updateRefinancePremiumProtocolBps(1);
    }

    function testCannotUpdateRefinancePremiumProtocolFee_max_fee() public {
        hevm.expectRevert("max fee");
        niftyApes.updateRefinancePremiumProtocolBps(1001);
    }

    function testUpdateRefinancePremiumProtocolFee_owner() public {
        assertEq(niftyApes.refinancePremiumProtocolBps(), 0);
        hevm.expectEmit(true, false, false, true);

        emit RefinancePremiumProtocolBpsUpdated(0, 1);
        niftyApes.updateRefinancePremiumProtocolBps(1);
        assertEq(niftyApes.refinancePremiumProtocolBps(), 1);
    }
}
