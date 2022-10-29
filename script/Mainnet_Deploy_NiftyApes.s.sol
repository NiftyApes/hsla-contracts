pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "@openzeppelin-norm/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin-norm/contracts/proxy/transparent/ProxyAdmin.sol";

import "../src/Liquidity.sol";
import "../src/Offers.sol";
import "../src/SigLending.sol";
import "../src/Lending.sol";

contract DeployNiftyApesScript is Script {
    function run() external {
        NiftyApesLending lending;
        NiftyApesOffers offers;
        NiftyApesLiquidity liquidity;
        NiftyApesSigLending sigLending;

        address compContractAddress = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        address mainnetMultisigAddress = 0xbe9B799D066A51F77d353Fc72e832f3803789362;

        vm.startBroadcast();

        liquidity = new NiftyApesLiquidity();
        liquidity.initialize(compContractAddress);

        offers = new NiftyApesOffers();
        offers.initialize(address(liquidity));

        sigLending = new NiftyApesSigLending();
        sigLending.initialize(address(offers));

        lending = new NiftyApesLending();
        lending.initialize(address(liquidity), address(offers), address(sigLending));

        liquidity.updateLendingContractAddress(address(lending));

        offers.updateLendingContractAddress(address(lending));
        offers.updateSigLendingContractAddress(address(sigLending));

        sigLending.updateLendingContractAddress(address(lending));

        // Mainnet Addresses
        address daiToken = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address cDAIToken = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
        address ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address cEtherToken = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

        // DAI
        liquidity.setCAssetAddress(daiToken, cDAIToken);

        uint256 cDAIAmount = liquidity.assetAmountToCAssetAmount(daiToken, type(uint256).max);

        liquidity.setMaxCAssetBalance(cDAIToken, cDAIAmount);

        // ETH
        liquidity.setCAssetAddress(ETH_ADDRESS, cEtherToken);

        uint256 cEtherAmount = liquidity.assetAmountToCAssetAmount(ETH_ADDRESS, type(uint256).max);

        liquidity.setMaxCAssetBalance(cEtherToken, cEtherAmount);

        liquidity.transferOwnership(mainnetMultisigAddress);
        lending.transferOwnership(mainnetMultisigAddress);
        offers.transferOwnership(mainnetMultisigAddress);
        sigLending.transferOwnership(mainnetMultisigAddress);

        vm.stopBroadcast();
    }
}
