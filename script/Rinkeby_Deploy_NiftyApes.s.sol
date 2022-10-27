pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Liquidity.sol";
import "../src/Offers.sol";
import "../src/SigLending.sol";
import "../src/Lending.sol";
import "../src/FlashClaim.sol";
import "../src/FlashPurchase.sol";
import "../src/FlashSell.sol";
import "../src/SellOnSeaport.sol";

contract DeployNiftyApesScript is Script {
    function run() external {
        NiftyApesLending lendingAuction;
        NiftyApesOffers offersContract;
        NiftyApesLiquidity liquidityProviders;
        NiftyApesSigLending sigLendingAuction;
        NiftyApesFlashClaim flashClaim;
        NiftyApesFlashPurchase flashPurchase;
        NiftyApesFlashSell flashSell;
        NiftyApesSellOnSeaport sellOnSeaport;
        address compContractAddress = 0xbbEB7c67fa3cfb40069D19E598713239497A3CA5;
        address seaportContractAddress = 0x00000000006c3852cbEf3e08E8dF289169EdE581;
        vm.startBroadcast();

        flashClaim = new NiftyApesFlashClaim();
        flashClaim.initialize();

        flashPurchase = new NiftyApesFlashPurchase();
        flashPurchase.initialize();

        liquidityProviders = new NiftyApesLiquidity();
        liquidityProviders.initialize(compContractAddress, address(flashPurchase));

        offersContract = new NiftyApesOffers();
        offersContract.initialize(address(liquidityProviders), address(flashPurchase));

        sigLendingAuction = new NiftyApesSigLending();
        sigLendingAuction.initialize(address(offersContract), address(flashPurchase));

        flashSell = new NiftyApesFlashSell();
        flashSell.initialize();

        sellOnSeaport = new NiftyApesSellOnSeaport();
        sellOnSeaport.initialize();

        lendingAuction = new NiftyApesLending();
        lendingAuction.initialize(
            address(liquidityProviders),
            address(offersContract),
            address(sigLendingAuction),
            address(flashClaim),
            address(flashPurchase),
            address(flashSell),
            address(sellOnSeaport)
        );

        liquidityProviders.updateLendingContractAddress(address(lendingAuction));

        offersContract.updateLendingContractAddress(address(lendingAuction));
        offersContract.updateSigLendingContractAddress(address(sigLendingAuction));

        sigLendingAuction.updateLendingContractAddress(address(lendingAuction));

        flashClaim.updateLendingContractAddress(address(lendingAuction));

        flashPurchase.updateLiquidityContractAddress(address(liquidityProviders));
        flashPurchase.updateOffersContractAddress(address(offersContract));
        flashPurchase.updateLendingContractAddress(address(lendingAuction));
        flashPurchase.updateSigLendingContractAddress(address(sigLendingAuction));

        flashSell.updateLendingContractAddress(address(lendingAuction));
        flashSell.updateLiquidityContractAddress(address(liquidityProviders));

        sellOnSeaport.updateLendingContractAddress(address(lendingAuction));
        sellOnSeaport.updateLiquidityContractAddress(address(liquidityProviders));
        sellOnSeaport.updateSeaportContractAddress(seaportContractAddress);

        // Rinkeby Addresses
        address daiToken = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address cDAIToken = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
        address ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address cEtherToken = 0xd6801a1DfFCd0a410336Ef88DeF4320D6DF1883e;

        // DAI
        liquidityProviders.setCAssetAddress(daiToken, cDAIToken);

        // ETH
        liquidityProviders.setCAssetAddress(ETH_ADDRESS, cEtherToken);

        // pauseSanctions for Rinkeby as Chainalysis contacts doent exists there
        liquidityProviders.pauseSanctions();
        lendingAuction.pauseSanctions();
        flashClaim.pauseSanctions();
        flashSell.pauseSanctions();

        vm.stopBroadcast();
    }
}
