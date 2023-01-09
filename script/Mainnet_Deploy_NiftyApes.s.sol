pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "@openzeppelin-norm/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin-norm/contracts/proxy/transparent/ProxyAdmin.sol";

import "../src/interfaces/niftyapes/lending/ILending.sol";
import "../src/interfaces/niftyapes/offers/IOffers.sol";
import "../src/interfaces/niftyapes/liquidity/ILiquidity.sol";
import "../src/interfaces/niftyapes/sigLending/ISigLending.sol";
import "../src/interfaces/Ownership.sol";

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
    NiftyApesRefinance refinanceImplementation;
    NiftyApesFlashClaim flashClaimImplementation;
    NiftyApesFlashPurchase flashPurchaseImplementation;
    NiftyApesFlashSell flashSellImplementation;
    NiftyApesSellOnSeaport sellOnSeaportImplementation;

    ProxyAdmin lendingProxyAdmin;
    ProxyAdmin offersProxyAdmin;
    ProxyAdmin liquidityProxyAdmin;
    ProxyAdmin sigLendingProxyAdmin;
    ProxyAdmin refinanceProxyAdmin;
    ProxyAdmin flashClaimProxyAdmin;
    ProxyAdmin flashPurchaseProxyAdmin;
    ProxyAdmin flashSellProxyAdmin;
    ProxyAdmin sellOnSeaportProxyAdmin;

    TransparentUpgradeableProxy lendingProxy;
    TransparentUpgradeableProxy offersProxy;
    TransparentUpgradeableProxy liquidityProxy;
    TransparentUpgradeableProxy sigLendingProxy;
    TransparentUpgradeableProxy refinanceProxy;
    TransparentUpgradeableProxy flashClaimProxy;
    TransparentUpgradeableProxy flashPurchaseProxy;
    TransparentUpgradeableProxy flashSellProxy;
    TransparentUpgradeableProxy sellOnSeaportProxy;

    ILending lending;
    IOffers offers;
    ILiquidity liquidity;
    ISigLending sigLending;
    IRefinance refinance;
    IFlashClaim flashClaim;
    IFlashPurchase flashPurchase;
    IFlashSell flashSell;
    ISellOnSeaport sellOnSeaport;

    function run() external {
        address compContractAddress = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        address mainnetMultisigAddress = 0xbe9B799D066A51F77d353Fc72e832f3803789362;

        vm.startBroadcast();

        // deploy and initialize implementation contracts
        flashClaimImplementation = new NiftyApesFlashClaim();
        flashClaimImplementation.initialize();

        flashPurchaseImplementation = new NiftyApesFlashPurchase();
        flashPurchaseImplementation.initialize();

        flashSellImplementation = new NiftyApesFlashSell();
        flashSellImplementation.initialize();

        sellOnSeaportImplementation = new NiftyApesSellOnSeaport();
        sellOnSeaportImplementation.initialize();

        refinanceImplementation = new NiftyApesRefinance();
        refinanceImplementation.initialize();

        liquidityImplementation = new NiftyApesLiquidity();
        liquidityImplementation.initialize(address(0), address(0), address(0));

        offersImplementation = new NiftyApesOffers();
        offersImplementation.initialize(address(0), address(0), address(0));

        sigLendingImplementation = new NiftyApesSigLending();
        sigLendingImplementation.initialize(address(0), address(0));

        lendingImplementation = new NiftyApesLending();
        lendingImplementation.initialize(address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0));

        // deploy proxy admins
        lendingProxyAdmin = new ProxyAdmin();
        offersProxyAdmin = new ProxyAdmin();
        liquidityProxyAdmin = new ProxyAdmin();
        sigLendingProxyAdmin = new ProxyAdmin();
        refinanceProxyAdmin = new ProxyAdmin();
        flashClaimProxyAdmin = new ProxyAdmin();
        flashPurchaseProxyAdmin = new ProxyAdmin();
        flashSellProxyAdmin = new ProxyAdmin();
        sellOnSeaportProxyAdmin = new ProxyAdmin();

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

        refinanceProxy = new TransparentUpgradeableProxy(
            address(refinanceImplementation),
            address(refinanceProxyAdmin),
            bytes("")
        );

        flashClaimProxy = new TransparentUpgradeableProxy(
            address(flashClaimImplementation),
            address(flashClaimProxyAdmin),
            bytes("")
        );

        flashPurchaseProxy = new TransparentUpgradeableProxy(
            address(flashPurchaseImplementation),
            address(flashPurchaseProxyAdmin),
            bytes("")
        );

        flashSellProxy = new TransparentUpgradeableProxy(
            address(flashSellImplementation),
            address(flashSellProxyAdmin),
            bytes("")
        );

        sellOnSeaportProxy = new TransparentUpgradeableProxy(
            address(sellOnSeaportImplementation),
            address(sellOnSeaportProxyAdmin),
            bytes("")
        );

        // declare interfaces
        lending = ILending(address(lendingProxy));
        liquidity = ILiquidity(address(liquidityProxy));
        offers = IOffers(address(offersProxy));
        sigLending = ISigLending(address(sigLendingProxy));
        refinance = IRefinance(address(refinanceProxy));
        flashClaim = IFlashClaim(address(flashClaimProxy));
        flashPurchase = IFlashPurchase(address(flashPurchaseProxy));
        flashSell = IFlashSell(address(flashSellProxy));
        sellOnSeaport = ISellOnSeaport(address(sellOnSeaportProxy));

        liquidity.initialize(address(compContractAddress), address(refinance), address(flashPurchase));
        offers.initialize(address(liquidity), address(refinance), address(flashPurchase));
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
        refinance.initialize();
        flashClaim.initialize();
        flashPurchase.initialize();
        flashSell.initialize();
        sellOnSeaport.initialize();

        liquidity.updateLendingContractAddress(address(lending));
        liquidity.updateRefinanceContractAddress(address(refinance));

        offers.updateLendingContractAddress(address(lending));
        offers.updateSigLendingContractAddress(address(sigLending));

        sigLending.updateLendingContractAddress(address(lending));

        refinance.updateLendingContractAddress(address(lending));
        refinance.updateLiquidityContractAddress(address(liquidity));
        refinance.updateOffersContractAddress(address(offers));
        refinance.updateSigLendingContractAddress(address(sigLending));

        flashClaim.updateLendingContractAddress(address(lending));

        flashPurchase.updateLiquidityContractAddress(address(liquidity));
        flashPurchase.updateOffersContractAddress(address(offers));
        flashPurchase.updateLendingContractAddress(address(lending));
        flashPurchase.updateSigLendingContractAddress(address(sigLending));

        flashSell.updateLendingContractAddress(address(lending));
        flashSell.updateLiquidityContractAddress(address(liquidity));

        sellOnSeaport.updateLendingContractAddress(address(lending));
        sellOnSeaport.updateLiquidityContractAddress(address(liquidity));
        sellOnSeaport.updateSeaportContractAddress(0x00000000006c3852cbEf3e08E8dF289169EdE581);

        // Mainnet Addresses
        address daiToken = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address cDAIToken = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
        address ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address cEtherToken = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

        // DAI
        liquidity.setCAssetAddress(daiToken, cDAIToken);

        uint256 cDAIAmount = liquidity.assetAmountToCAssetAmount(daiToken, type(uint128).max);

        liquidity.setMaxCAssetBalance(cDAIToken, cDAIAmount);

        // ETH
        liquidity.setCAssetAddress(ETH_ADDRESS, cEtherToken);

        uint256 cEtherAmount = liquidity.assetAmountToCAssetAmount(ETH_ADDRESS, type(uint128).max);

        liquidity.setMaxCAssetBalance(cEtherToken, cEtherAmount);

        // change ownership of proxies
        IOwnership(address(lendingProxy)).transferOwnership(mainnetMultisigAddress);
        IOwnership(address(offersProxy)).transferOwnership(mainnetMultisigAddress);
        IOwnership(address(liquidityProxy)).transferOwnership(mainnetMultisigAddress);
        IOwnership(address(sigLendingProxy)).transferOwnership(mainnetMultisigAddress);
        IOwnership(address(refinance)).transferOwnership(mainnetMultisigAddress);
        IOwnership(address(flashClaim)).transferOwnership(mainnetMultisigAddress);
        IOwnership(address(flashPurchase)).transferOwnership(mainnetMultisigAddress);
        IOwnership(address(flashSell)).transferOwnership(mainnetMultisigAddress);
        IOwnership(address(sellOnSeaport)).transferOwnership(mainnetMultisigAddress);

        // change ownership of proxyAdmin
        lendingProxyAdmin.transferOwnership(mainnetMultisigAddress);
        offersProxyAdmin.transferOwnership(mainnetMultisigAddress);
        liquidityProxyAdmin.transferOwnership(mainnetMultisigAddress);
        sigLendingProxyAdmin.transferOwnership(mainnetMultisigAddress);
        refinanceProxyAdmin.transferOwnership(mainnetMultisigAddress);
        flashClaimProxyAdmin.transferOwnership(mainnetMultisigAddress);
        flashPurchaseProxyAdmin.transferOwnership(mainnetMultisigAddress);
        flashSellProxyAdmin.transferOwnership(mainnetMultisigAddress);
        sellOnSeaportProxyAdmin.transferOwnership(mainnetMultisigAddress);

        vm.stopBroadcast();
    }
}
