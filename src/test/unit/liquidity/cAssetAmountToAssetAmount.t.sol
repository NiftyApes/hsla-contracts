pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/liquidity/ILiquidityEvents.sol";
import "../../../interfaces/compound/ICERC20.sol";

contract TestCAssetAmountToAssetAmount is Test, ILiquidityEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function testCAssetAmountToAssetAmount() public {
        if (!integration) {
            cUSDCToken.setExchangeRateCurrent(220154645140434444389595003); // exchange rate of DAI at time of edit

            uint256 result = liquidity.cAssetAmountToAssetAmount(address(cUSDCToken), 1e8); // supply 1 mockCUSDC, would be better to call this mock DAI as USDC has 6 decimals

            assertEq(result, 22015464514043444); // ~ 0.02 DAI
        } else {
            uint256 amtUsdc = usdcToken.balanceOf(lender1);

            vm.startPrank(lender1);
            ICERC20(address(usdcToken)).approve(address(cUSDCToken), amtUsdc);
            ICERC20(address(cUSDCToken)).mint(amtUsdc);

            uint256 amtCUsdc = cUSDCToken.balanceOf(lender1);

            uint256 result = liquidity.cAssetAmountToAssetAmount(address(cUSDCToken), amtCUsdc);

            ICERC20(address(cUSDCToken)).redeem(amtCUsdc);

            assertEq(usdcToken.balanceOf(lender1), result);
        }
    }
}
