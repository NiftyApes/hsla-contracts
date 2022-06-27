// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/liquidity/ILiquidityEvents.sol";

contract TestAssetAmountToCAssetAmount is Test, ILiquidityEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function testAssetAmountToAssetAmount() public {
        cUSDCToken.setExchangeRateCurrent(220154645140434444389595003); // recent exchange rate of DAI

        uint256 result = liquidity.assetAmountToCAssetAmount(address(usdcToken), 1e18); // supply 1 mockCUSDC, would be better to call this mock DAI as USDC has 6 decimals

        assertEq(result, 4542261642);
    }
}
