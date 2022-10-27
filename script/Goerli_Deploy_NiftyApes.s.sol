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
        address goerliMultisigAddress = 0x213dE8CcA7C414C0DE08F456F9c4a2Abc4104028;

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
        address daiToken = 0xdc31Ee1784292379Fbb2964b3B9C4124D8F89C60;
        address cDAIToken = 0x822397d9a55d0fefd20F5c4bCaB33C5F65bd28Eb;
        address ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address cEtherToken = 0x20572e4c090f15667cF7378e16FaD2eA0e2f3EfF;

        // DAI
        liquidityProviders.setCAssetAddress(daiToken, cDAIToken);

        // ETH
        liquidityProviders.setCAssetAddress(ETH_ADDRESS, cEtherToken);

        // pauseSanctions for Goerli as Chainalysis contacts doent exists there
        liquidityProviders.pauseSanctions();
        lendingAuction.pauseSanctions();

        liquidityProviders.transferOwnership(goerliMultisigAddress);
        lendingAuction.transferOwnership(goerliMultisigAddress);
        offersContract.transferOwnership(goerliMultisigAddress);
        sigLendingAuction.transferOwnership(goerliMultisigAddress);

        vm.stopBroadcast();
    }
}
