pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Liquidity.sol";
import "../src/Offers.sol";
import "../src/SigLending.sol";
import "../src/Lending.sol";

contract DeployNiftyApesScript is Script {
    function run() external {
        NiftyApesLending lendingAuction;
        NiftyApesOffers offersContract;
        NiftyApesLiquidity liquidityProviders;
        NiftyApesSigLending sigLendingAuction;

        address compContractAddress = 0xfa5E1B628EFB17C024ca76f65B45Faf6B3128CA5;

        vm.startBroadcast();

        liquidityProviders = new NiftyApesLiquidity();
        liquidityProviders.initialize(compContractAddress);

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

        // Goerli Addresses
        address daiToken = 0x73967c6a0904aA032C103b4104747E88c566B1A2;
        address cDAIToken = 0x92f44bE965c47ce72D13d40ea45637A8f92C0a28;
        address ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address cEtherToken = 0x20572e4c090f15667cF7378e16FaD2eA0e2f3EfF;

        // DAI - skip for now
        // liquidityProviders.setCAssetAddress(daiToken, cDAIToken);
        // uint256 cDAIAmount = liquidityProviders.assetAmountToCAssetAmount(daiToken, 500000);
        // liquidityProviders.setMaxCAssetBalance(cDAIToken, cDAIAmount);

        // ETH
        liquidityProviders.setCAssetAddress(ETH_ADDRESS, cEtherToken);

        liquidityProviders.setMaxCAssetBalance(cEtherToken, type(uint256).max);

        // pauseSanctions for Goerli
        liquidityProviders.pauseSanctions();
        lendingAuction.pauseSanctions();

        vm.stopBroadcast();
    }
}
