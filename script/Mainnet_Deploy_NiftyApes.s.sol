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
        address compContractAddress = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        address mainnetMultisigAddress = 0xbe9B799D066A51F77d353Fc72e832f3803789362;

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

        // Mainnet Addresses
        address daiToken = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address cDAIToken = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
        address ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address cEtherToken = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

        // DAI
        liquidityProviders.setCAssetAddress(daiToken, cDAIToken);

        uint256 cDAIAmount = liquidityProviders.assetAmountToCAssetAmount(
            daiToken,
            ~uint128(0) - 1
        );

        liquidityProviders.setMaxCAssetBalance(cDAIToken, cDAIAmount);

        // ETH
        liquidityProviders.setCAssetAddress(ETH_ADDRESS, cEtherToken);

        uint256 cEtherAmount = liquidityProviders.assetAmountToCAssetAmount(
            ETH_ADDRESS,
            ~uint128(0) - 1
        );

        liquidityProviders.setMaxCAssetBalance(cEtherToken, cEtherAmount);

        liquidityProviders.transferOwnership(mainnetMultisigAddress);
        lendingAuction.transferOwnership(mainnetMultisigAddress);
        offersContract.transferOwnership(mainnetMultisigAddress);
        sigLendingAuction.transferOwnership(mainnetMultisigAddress);

        vm.stopBroadcast();
    }
}
