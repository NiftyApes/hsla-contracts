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

        // Rinkeby Addresses
        address usdcToken = address(0xeb8f08a975Ab53E34D8a0330E0D34de942C95926);
        address cUSDCToken = address(0x5B281A6DdA0B271e91ae35DE655Ad301C976edb1);
        address ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        address cEtherToken = address(0xd6801a1DfFCd0a410336Ef88DeF4320D6DF1883e);

        // USDC
        liquidityProviders.setCAssetAddress(usdcToken, cUSDCToken);

        uint256 cUSDCAmount = liquidityProviders.assetAmountToCAssetAmount(usdcToken, 500_000);

        liquidityProviders.setMaxCAssetBalance(cUSDCToken, cUSDCAmount);

        // ETH
        liquidityProviders.setCAssetAddress(ETH_ADDRESS, cEtherToken);

        uint256 cEtherAmount = liquidityProviders.assetAmountToCAssetAmount(ETH_ADDRESS, 500_000);

        liquidityProviders.setMaxCAssetBalance(cEtherToken, cEtherAmount);

        // pauseSanctions for Rinkeby as Chainalysis contacts doent exists there
        liquidityProviders.pauseSanctions();
        lendingAuction.pauseSanctions();

        vm.stopBroadcast();
    }
}
