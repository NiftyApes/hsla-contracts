// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "@openzeppelin-norm/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin-norm/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/interfaces/niftyapes/lending/ILending.sol";
import "../src/interfaces/niftyapes/offers/IOffers.sol";
import "../src/interfaces/niftyapes/liquidity/ILiquidity.sol";
import "../src/interfaces/niftyapes/sigLending/ISigLending.sol";
import "../src/interfaces/ownership.sol";
import "../src/Liquidity.sol";
import "../src/Offers.sol";
import "../src/SigLending.sol";
import "../src/Lending.sol";
import "../src/FlashClaim.sol";
import "../src/FlashPurchase.sol";
import "../src/FlashSell.sol";
import "../src/SellOnSeaport.sol";
import "../src/Refinance.sol";

contract DeployNiftyApesScript is Script {
    NiftyApesLending lendingImplementation;
    NiftyApesOffers offersImplementation;
    NiftyApesLiquidity liquidityImplementation;
    NiftyApesSigLending sigLendingImplementation;

    ProxyAdmin lendingProxyAdmin;
    ProxyAdmin offersProxyAdmin;
    ProxyAdmin liquidityProxyAdmin;
    ProxyAdmin sigLendingProxyAdmin;

    TransparentUpgradeableProxy lendingProxy;
    TransparentUpgradeableProxy offersProxy;
    TransparentUpgradeableProxy liquidityProxy;
    TransparentUpgradeableProxy sigLendingProxy;

    ILending lending;
    IOffers offers;
    ILiquidity liquidity;
    ISigLending sigLending;

    NiftyApesFlashClaim flashClaim;
    NiftyApesFlashPurchase flashPurchase;
    NiftyApesFlashSell flashSell;
    NiftyApesSellOnSeaport sellOnSeaport;

    function run() external {
        address compContractAddress = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        address goerliMultisigAddress = 0x213dE8CcA7C414C0DE08F456F9c4a2Abc4104028;
        address seaportContractAddress = 0x00000000006c3852cbEf3e08E8dF289169EdE581;

        vm.startBroadcast();

        flashClaim = new NiftyApesFlashClaim();
        flashClaim.initialize();

        flashPurchase = new NiftyApesFlashPurchase();
        flashPurchase.initialize();

        flashSell = new NiftyApesFlashSell();
        flashSell.initialize();

        sellOnSeaport = new NiftyApesSellOnSeaport();
        sellOnSeaport.initialize();

        refinance = new NiftyApesRefinance();
        refinance.initialize();

        // deploy and initialize implementation contracts
        liquidityImplementation = new NiftyApesLiquidity();
        liquidityImplementation.initialize(address(0));

        offersImplementation = new NiftyApesOffers();
        offersImplementation.initialize(address(0));

        sigLendingImplementation = new NiftyApesSigLending();
        sigLendingImplementation.initialize(address(0));

        lendingImplementation = new NiftyApesLending();
        lendingImplementation.initialize(address(0), address(0), address(0));

        // deploy proxy admins
        lendingProxyAdmin = new ProxyAdmin();
        offersProxyAdmin = new ProxyAdmin();
        liquidityProxyAdmin = new ProxyAdmin();
        sigLendingProxyAdmin = new ProxyAdmin();

        // deploy proxies
        lendingProxy = new TransparentUpgradeableProxy(
            address(lendingImplementation),
            address(lendingProxyAdmin),
            bytes("")
        );
        offersProxy = new TransparentUpgradeableProxy(
            address(offersImplementation),
            address(offersProxyAdmin),
            bytes("")
        );
        liquidityProxy = new TransparentUpgradeableProxy(
            address(liquidityImplementation),
            address(liquidityProxyAdmin),
            bytes("")
        );

        sigLendingProxy = new TransparentUpgradeableProxy(
            address(sigLendingImplementation),
            address(sigLendingProxyAdmin),
            bytes("")
        );

        // declare interfaces
        lending = ILending(address(lendingProxy));
        liquidity = ILiquidity(address(liquidityProxy));
        offers = IOffers(address(offersProxy));
        sigLending = ISigLending(address(sigLendingProxy));

        // initialize proxies
        liquidity.initialize(address(compContractAddress), address(flashPurchase), address(refinance));
        offers.initialize(address(liquidity), address(flashPurchase), address(refinance));
        sigLending.initialize(address(offers), address(flashPurchase));
        lending.initialize(
            address(liquidity),
            address(offers),
            address(sigLending),
            address(refinance),
            address(flashClaim),
            address(flashPurchase),
            address(flashSell),
            address(sellOnSeaport)
        );

        liquidity.updateLendingContractAddress(address(lending));
        liquidity.updateRefinanceContractAddress(address(refinance));

        offers.updateLendingContractAddress(address(lending));
        offers.updateSigLendingContractAddress(address(sigLending));

        sigLending.updateLendingContractAddress(address(lending));

        flashClaim.updateLendingContractAddress(address(lending));

        flashPurchase.updateLiquidityContractAddress(address(liquidity));
        flashPurchase.updateOffersContractAddress(address(offers));
        flashPurchase.updateLendingContractAddress(address(lending));
        flashPurchase.updateSigLendingContractAddress(address(sigLending));

        flashSell.updateLendingContractAddress(address(lending));
        flashSell.updateLiquidityContractAddress(address(liquidity));

        sellOnSeaport.updateLendingContractAddress(address(lending));
        sellOnSeaport.updateLiquidityContractAddress(address(liquidity));
        sellOnSeaport.updateSeaportContractAddress(seaportContractAddress);

        refinance.updateLendingContractAddress(address(lending));
        refinance.updateLiquidityContractAddress(address(liquidity));
        refinance.updateOffersContractAddress(address(offers));
        refinance.updateSigLendingContractAddress(address(sigLending));

        // Goerli Addresses
        address daiToken = 0xdc31Ee1784292379Fbb2964b3B9C4124D8F89C60;
        address cDAIToken = 0x822397d9a55d0fefd20F5c4bCaB33C5F65bd28Eb;
        address ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address cEtherToken = 0x20572e4c090f15667cF7378e16FaD2eA0e2f3EfF;

        // DAI
        liquidity.setCAssetAddress(daiToken, cDAIToken);

        uint256 cDAIAmount = liquidity.assetAmountToCAssetAmount(daiToken, type(uint128).max);

        liquidity.setMaxCAssetBalance(cDAIToken, cDAIAmount);

        // ETH
        liquidity.setCAssetAddress(ETH_ADDRESS, cEtherToken);

        uint256 cEtherAmount = liquidity.assetAmountToCAssetAmount(ETH_ADDRESS, type(uint128).max);

        liquidity.setMaxCAssetBalance(cEtherToken, cEtherAmount);

        // pauseSanctions for Goerli as Chainalysis contacts doent exists there
        liquidity.pauseSanctions();
        lending.pauseSanctions();

        liquidity.transferOwnership(goerliMultisigAddress);
        lending.transferOwnership(goerliMultisigAddress);
        offers.transferOwnership(goerliMultisigAddress);
        sigLending.transferOwnership(goerliMultisigAddress);
        flashClaim.transferOwnership(goerliMultisigAddress);
        flashPurchase.transferOwnership(goerliMultisigAddress);
        flashSell.transferOwnership(goerliMultisigAddress);
        sellOnSeaport.transferOwnership(goerliMultisigAddress);
        refinance.transferOwnership(goerliMultisigAddress);

        vm.stopBroadcast();
    }
}
