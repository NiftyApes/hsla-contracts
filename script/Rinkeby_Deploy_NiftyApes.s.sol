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
        address compContractAddress = 0xbbEB7c67fa3cfb40069D19E598713239497A3CA5;
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

        // Rinkeby Addresses
        address daiToken = 0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735;
        address cDAIToken = 0x6D7F0754FFeb405d23C51CE938289d4835bE3b14;
        address ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address cEtherToken = 0xd6801a1DfFCd0a410336Ef88DeF4320D6DF1883e;

        // DAI
        liquidityProviders.setCAssetAddress(daiToken, cDAIToken);

        uint256 cDAIAmount = liquidityProviders.assetAmountToCAssetAmount(daiToken, 500000);

        liquidityProviders.setMaxCAssetBalance(cDAIToken, cDAIAmount);

        // ETH
        liquidityProviders.setCAssetAddress(ETH_ADDRESS, cEtherToken);

        uint256 cEtherAmount = liquidityProviders.assetAmountToCAssetAmount(ETH_ADDRESS, 500);

        liquidityProviders.setMaxCAssetBalance(cEtherToken, cEtherAmount);

        // pauseSanctions for Rinkeby as Chainalysis contacts doent exists there
        liquidityProviders.pauseSanctions();
        lendingAuction.pauseSanctions();

        vm.stopBroadcast();
    }
}
