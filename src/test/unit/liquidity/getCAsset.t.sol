// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";
import "../../../interfaces/niftyapes/liquidity/ILiquidityEvents.sol";

contract TestGetCAsset is Test, ILiquidityEvents, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function test_unit_getCAsset_works() public {
        if (!integration) {
            assertEq(
                liquidity.getCAsset(address(usdcToken)),
                0x0C7BBB021d72dB4FfBa37bDF4ef055eECdbc0a29
            );
        } else {
            assertEq(
                liquidity.getCAsset(address(usdcToken)),
                address(0x39AA39c021dfbaE8faC545936693aC917d5E7563)
            );
        }
    }
}
