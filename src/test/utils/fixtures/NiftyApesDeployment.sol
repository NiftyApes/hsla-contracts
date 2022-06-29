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
    address compContractAddress = 0xbbEB7c67fa3cfb40069D19E598713239497A3CA5;

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);

        liquidity = new NiftyApesLiquidity();
        liquidity.initialize(compContractAddress);

        offers = new NiftyApesOffers();
        offers.initialize(address(liquidity));

        sigLending = new NiftyApesSigLending();
        sigLending.initialize(address(offers));

        lending = new NiftyApesLending();
        lending.initialize(address(liquidity), address(offers), address(sigLending));

        sigLending.updateLendingContractAddress(address(lending));

        offers.updateLendingContractAddress(address(lending));
        offers.updateSigLendingContractAddress(address(sigLending));

        liquidity.updateLendingContractAddress(address(lending));

        liquidity.setCAssetAddress(ETH_ADDRESS, address(cEtherToken));
        liquidity.setMaxCAssetBalance(address(cEtherToken), ~uint256(0));

        liquidity.setCAssetAddress(address(usdcToken), address(cUSDCToken));
        liquidity.setMaxCAssetBalance(address(cUSDCToken), ~uint256(0));

        vm.stopPrank();

        vm.label(address(0), "NULL !!!!! ");
    }
}
