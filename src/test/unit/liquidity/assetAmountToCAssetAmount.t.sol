pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/liquidity/ILiquidityEvents.sol";
import "../../../interfaces/compound/ICERC20.sol";

contract TestAssetAmountToCAssetAmount is Test, ILiquidityEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function testAssetAmountToCAssetAmount() public {
        if (!integration) {
            cUSDCToken.setExchangeRateCurrent(220154645140434444389595003); // recent exchange rate of DAI

            uint256 result = liquidity.assetAmountToCAssetAmount(address(usdcToken), 1e18); // supply 1 mockCUSDC, would be better to call this mock DAI as USDC has 6 decimals

            assertEq(result, 4542261642);
        } else {
            uint256 amtUsdc = usdcToken.balanceOf(lender1);

            uint256 result = liquidity.assetAmountToCAssetAmount(address(usdcToken), amtUsdc);

            uint256 exchangeRateCurrent = ICERC20(address(cUSDCToken)).exchangeRateCurrent();

            uint256 cTokenAmount = (amtUsdc * (10**18)) / exchangeRateCurrent;

            assertEq(result, cTokenAmount);

            // This mints the same amount of cUSDC directly
            // i.e., just interacting with Compound and not via NiftyApes
            // to double check the above math
            vm.startPrank(lender1);
            ICERC20(address(usdcToken)).approve(address(cUSDCToken), amtUsdc);
            ICERC20(address(cUSDCToken)).mint(amtUsdc);
            assertEq(cUSDCToken.balanceOf(lender1), result);
            vm.stopPrank();
        }
    }
}
