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
// adds cAssets for both ETH and DAI
// sets max cAsset balance for both to unint256 max
contract NiftyApesDeployment is Test, NFTAndERC20Fixtures {
    NiftyApesLending lendingImplementation;
    NiftyApesOffers offersImplementation;
    NiftyApesLiquidity liquidityImplementation;
    NiftyApesSigLending sigLendingImplementation;

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);

        // deploy and initialize implementation contracts
        liquidityImplementation = new NiftyApesLiquidity();
        liquidityImplementation.initialize(address(compToken));

        offersImplementation = new NiftyApesOffers();
        offersImplementation.initialize(address(liquidityImplementation));

        sigLendingImplementation = new NiftyApesSigLending();
        sigLendingImplementation.initialize(address(offersImplementation));

        lendingImplementation = new NiftyApesLending();
        lendingImplementation.initialize(
            address(liquidityImplementation),
            address(offersImplementation),
            address(sigLendingImplementation)
        );

        vm.stopPrank();

        vm.label(address(0), "NULL !!!!! ");
    }
}
