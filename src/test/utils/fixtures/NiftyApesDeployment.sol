// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../Lending.sol";
import "../../../Liquidity.sol";
import "../../../Offers.sol";
import "../../../SigLending.sol";
import "./NFTAndERC20Fixtures.sol";

import "forge-std/Test.sol";

// deploy & initializes NiftyApes contracts
// connects them to one another
// adds cAssets for both ETH and USDC
// sets max cAsset balance for both to unint256 max
contract NiftyApesDeployment is Test, NFTAndERC20Fixtures {
    NiftyApesLending lending;
    NiftyApesOffers offers;
    NiftyApesLiquidity liquidity;
    NiftyApesSigLending sigLending;

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);

        lending = new NiftyApesLending();
        lending.initialize();

        liquidity = new NiftyApesLiquidity();
        liquidity.initialize();

        offers = new NiftyApesOffers();
        offers.initialize();

        sigLending = new NiftyApesSigLending();
        sigLending.initialize();

        lending.updateOffersContractAddress(address(offers));
        lending.updateLiquidityContractAddress(address(liquidity));
        lending.updateSigLendingContractAddress(address(sigLending));

        liquidity.updateLendingContractAddress(address(lending));

        offers.updateLendingContractAddress(address(lending));
        offers.updateLiquidityContractAddress(address(liquidity));
        offers.updateSigLendingContractAddress(address(sigLending));

        sigLending.updateLendingContractAddress(address(lending));
        sigLending.updateOffersContractAddress(address(offers));

        liquidity.setCAssetAddress(ETH_ADDRESS, address(cEtherToken));
        liquidity.setMaxCAssetBalance(ETH_ADDRESS, ~uint256(0));

        liquidity.setCAssetAddress(address(usdcToken), address(cUSDCToken));
        liquidity.setMaxCAssetBalance(address(usdcToken), ~uint256(0));

        vm.stopPrank();
    }
}
