// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin-norm/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin-norm/contracts/proxy/transparent/ProxyAdmin.sol";

import "../../../interfaces/niftyapes/lending/ILending.sol";
import "../../../interfaces/niftyapes/offers/IOffers.sol";
import "../../../interfaces/niftyapes/liquidity/ILiquidity.sol";
import "../../../interfaces/niftyapes/sigLending/ISigLending.sol";

import "../../../Lending.sol";
import "../../../Liquidity.sol";
import "../../../Offers.sol";
import "../../../SigLending.sol";
import "../../../FlashClaim.sol";
import "./FlashClaimReceivers/FlashClaimReceiverTestHappy.sol";
import "./FlashClaimReceivers/FlashClaimReceiverTestNoReturn.sol";
import "../../../FlashPurchase.sol";
import "../../../flashPurchase/integrations/SeaportFlashPurchaseIntegration.sol";
import "../../../flashPurchase/integrations/SudoswapFlashPurchaseIntegration.sol";
import "../../../FlashSell.sol";
import "../../../flashSell/integrations/SeaportFlashSellIntegration.sol";
import "../../../SellOnSeaport.sol";
import "../../../Refinance.sol";
import "../../../flashSell/integrations/SudoswapFlashSellIntegration.sol";
import "./NFTAndERC20Fixtures.sol";
import "../../../interfaces/seaport/ISeaport.sol";

import "forge-std/Test.sol";

// deploy & initializes NiftyApes contracts
// connects them to one another
// adds cAssets for both ETH and DAI
// sets max cAsset balance for both to uint256 max
contract NiftyApesDeployment is Test, NFTAndERC20Fixtures {
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

        NiftyApesRefinance refinance;
        NiftyApesFlashClaim flashClaim;
        FlashClaimReceiverBaseHappy flashClaimReceiverHappy;
        FlashClaimReceiverBaseNoReturn flashClaimReceiverNoReturn;
        NiftyApesFlashPurchase flashPurchase;
        SeaportFlashPurchaseIntegration seaportFlashPurchase;
        SudoswapFlashPurchaseIntegration sudoswapFlashPurchase;
        NiftyApesFlashSell flashSell;
        SeaportFlashSellIntegration seaportFlashSell;
        NiftyApesSellOnSeaport sellOnSeaport;
        SudoswapFlashSellIntegration sudoswapFlashSell;

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant SEAPORT_ADDRESS = 0x00000000006c3852cbEf3e08E8dF289169EdE581;
    address constant SUDOSWAP_FACTORY_ADDRESS = 0xb16c1342E617A5B6E4b631EB114483FDB289c0A4;
    address constant SUDOSWAP_ROUTER_ADDRESS = 0x2B2e8cDA09bBA9660dCA5cB6233787738Ad68329;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);

        flashClaimReceiverHappy = new FlashClaimReceiverBaseHappy();
        flashClaimReceiverNoReturn = new FlashClaimReceiverBaseNoReturn();

        flashClaim = new NiftyApesFlashClaim();
        flashClaim.initialize();

        flashSell = new NiftyApesFlashSell();
        flashSell.initialize();

        seaportFlashSell = new SeaportFlashSellIntegration();
        seaportFlashSell.initialize();

        sudoswapFlashSell = new SudoswapFlashSellIntegration();
        sudoswapFlashSell.initialize();

        sellOnSeaport = new NiftyApesSellOnSeaport();
        sellOnSeaport.initialize();

        flashPurchase = new NiftyApesFlashPurchase();
        flashPurchase.initialize();

        if (integration) {
            seaportFlashPurchase = new SeaportFlashPurchaseIntegration();
            seaportFlashPurchase.initialize(
                address(offers),
                address(flashPurchase),
                SEAPORT_ADDRESS
            );

            sudoswapFlashPurchase = new SudoswapFlashPurchaseIntegration();
            sudoswapFlashPurchase.initialize(
                address(offers),
                address(flashPurchase),
                SUDOSWAP_FACTORY_ADDRESS,
                SUDOSWAP_ROUTER_ADDRESS
            );

            sellOnSeaport.updateSeaportContractAddress(SEAPORT_ADDRESS);
            seaportFlashSell.updateSeaportContractAddress(SEAPORT_ADDRESS);

            sudoswapFlashSell.updateFlashSellContractAddress(address(flashSell));
            sudoswapFlashSell.updateSudoswapFactoryContractAddress(SUDOSWAP_FACTORY_ADDRESS);
            sudoswapFlashSell.updateSudoswapRouterContractAddress(SUDOSWAP_ROUTER_ADDRESS);
        } else {
            seaportFlashPurchase = new SeaportFlashPurchaseIntegration();
            sudoswapFlashPurchase = new SudoswapFlashPurchaseIntegration();
        }

        refinance = new NiftyApesRefinance();
        refinance.initialize();

        // deploy and initialize implementation contracts
        liquidityImplementation = new NiftyApesLiquidity();
        liquidityImplementation.initialize(address(compToken));

        offersImplementation = new NiftyApesOffers();
        offersImplementation.initialize(address(liquidityImplementation));

        sigLendingImplementation = new NiftyApesSigLending();
        sigLendingImplementation.initialize(address(offersImplementation));

        lendingImplementation = new NiftyApesLending();
        lendingImplementation.initialize(
            address(liquidityImplementation),
            address(offersImplementation),
            address(sigLendingImplementation)
        );

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


        liquidity.initialize(address(compToken));

        offers.initialize(address(liquidity));

        sigLending.initialize(address(offers));

        lending.initialize(address(liquidity), address(offers), address(sigLending));

        sigLending.updateLendingContractAddress(address(lending));
        sigLending.updateRefinanceContractAddress(address(refinance));

        refinance.updateLendingContractAddress(address(lending));
        refinance.updateLiquidityContractAddress(address(liquidity));
        refinance.updateOffersContractAddress(address(offers));
        refinance.updateSigLendingContractAddress(address(sigLending));

        offers.updateLendingContractAddress(address(lending));
        offers.updateSigLendingContractAddress(address(sigLending));

        liquidity.updateLendingContractAddress(address(lending));

        flashClaim.updateLendingContractAddress(address(lending));

        flashPurchase.updateLiquidityContractAddress(address(liquidity));
        flashPurchase.updateOffersContractAddress(address(offers));
        flashPurchase.updateLendingContractAddress(address(lending));
        flashPurchase.updateSigLendingContractAddress(address(sigLending));
        seaportFlashPurchase.updateOffersContractAddress(address(offers));
        sudoswapFlashPurchase.updateOffersContractAddress(address(offers));

        flashSell.updateLendingContractAddress(address(lending));
        flashSell.updateLiquidityContractAddress(address(liquidity));

        seaportFlashSell.updateFlashSellContractAddress(address(flashSell));
        seaportFlashSell.updateWethContractAddress(address(wethToken));

        flashClaimReceiverHappy.updateFlashClaimContractAddress(address(flashClaim));

        sellOnSeaport.updateLendingContractAddress(address(lending));
        sellOnSeaport.updateLiquidityContractAddress(address(liquidity));

        // update protocol interest
        lending.updateProtocolInterestBps(100);
        lending.updateDefaultRefinancePremiumBps(25);

        // set max balances
        liquidity.setCAssetAddress(ETH_ADDRESS, address(cEtherToken));
        liquidity.setMaxCAssetBalance(address(cEtherToken), ~uint256(0));

        liquidity.setCAssetAddress(address(daiToken), address(cDAIToken));
        liquidity.setMaxCAssetBalance(address(cDAIToken), ~uint256(0));

        if (!integration) {
            liquidity.pauseSanctions();
            lending.pauseSanctions();
            flashClaim.pauseSanctions();
            flashSell.pauseSanctions();
        }

        vm.stopPrank();

        vm.label(address(0), "NULL !!!!! ");
    }
}
