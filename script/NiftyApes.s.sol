pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Liquidity.sol";
import "../src/Offers.sol";
import "../src/SigLending.sol";
import "../src/Lending.sol";

contract NiftyApesScript is Script {
    function run() external {
        NiftyApesLending lendingAuction;
        NiftyApesOffers offersContract;
        NiftyApesLiquidity liquidityProviders;
        NiftyApesSigLending sigLendingAuction;
        vm.startBroadcast();

        liquidityProviders = new NiftyApesLiquidity();
        liquidityProviders.initialize();

        offersContract = new NiftyApesOffers();
        offersContract.initialize(address(liquidityProviders));

        sigLendingAuction = new NiftyApesSigLending();
        sigLendingAuction.initialize(address(offersContract));

        lendingAuction = new NiftyApesLending();
        lendingAuction.initialize(
            address(liquidityProviders),
            address(offersContract),
            address(sigLendingAuction)
        );

        liquidityProviders.updateLendingContractAddress(address(lendingAuction));

        offersContract.updateLendingContractAddress(address(lendingAuction));
        offersContract.updateSigLendingContractAddress(address(sigLendingAuction));

        sigLendingAuction.updateLendingContractAddress(address(lendingAuction));

        vm.stopBroadcast();
    }
}
