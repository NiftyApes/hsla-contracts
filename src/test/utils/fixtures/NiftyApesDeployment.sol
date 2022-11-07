// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

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
import "../../../SellOnSeaport.sol";
import "./NFTAndERC20Fixtures.sol";
import "../../../interfaces/seaport/ISeaport.sol";

import "forge-std/Test.sol";

// deploy & initializes NiftyApes contracts
// connects them to one another
// adds cAssets for both ETH and DAI
// sets max cAsset balance for both to unint256 max
contract NiftyApesDeployment is Test, NFTAndERC20Fixtures {
    NiftyApesLending lending;
    NiftyApesOffers offers;
    NiftyApesLiquidity liquidity;
    NiftyApesSigLending sigLending;
    NiftyApesFlashClaim flashClaim;
    FlashClaimReceiverBaseHappy flashClaimReceiverHappy;
    FlashClaimReceiverBaseNoReturn flashClaimReceiverNoReturn;
    NiftyApesFlashPurchase flashPurchase;
    SeaportFlashPurchaseIntegration seaportFlashPurchase;
    SudoswapFlashPurchaseIntegration sudoswapFlashPurchase;
    NiftyApesFlashSell flashSell;
    NiftyApesSellOnSeaport sellOnSeaport;

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

        sellOnSeaport = new NiftyApesSellOnSeaport();
        sellOnSeaport.initialize();

        if (integration) {
            flashPurchase = new NiftyApesFlashPurchase();

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

        } else {
            flashPurchase = new NiftyApesFlashPurchase();
            seaportFlashPurchase = new SeaportFlashPurchaseIntegration();
            sudoswapFlashPurchase = new SudoswapFlashPurchaseIntegration();
        }

        liquidity = new NiftyApesLiquidity();
        liquidity.initialize(address(compToken), address(flashPurchase));

        offers = new NiftyApesOffers();
        offers.initialize(address(liquidity), address(flashPurchase));

        sigLending = new NiftyApesSigLending();
        sigLending.initialize(address(offers), address(flashPurchase));

        flashSell = new NiftyApesFlashSell();
        flashSell.initialize();

        lending = new NiftyApesLending();
        lending.initialize(
            address(liquidity),
            address(offers),
            address(sigLending),
            address(flashClaim),
            address(flashPurchase),
            address(flashSell),
            address(sellOnSeaport)
        );

        flashPurchase.initialize();

        sigLending.updateLendingContractAddress(address(lending));

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

        liquidity.setCAssetAddress(ETH_ADDRESS, address(cEtherToken));
        liquidity.setMaxCAssetBalance(address(cEtherToken), ~uint256(0));

        liquidity.setCAssetAddress(address(daiToken), address(cDAIToken));
        liquidity.setMaxCAssetBalance(address(cDAIToken), ~uint256(0));

        flashClaimReceiverHappy.updateFlashClaimContractAddress(address(flashClaim));

        sellOnSeaport.updateLendingContractAddress(address(lending));
        sellOnSeaport.updateLiquidityContractAddress(address(liquidity));
        sellOnSeaport.updateFlashSellContractAddress(address(flashSell));
        sellOnSeaport.updateFlashSellContractAddress(address(flashSell));
        sellOnSeaport.updateWethContractAddress(address(wethToken));

        lending.updateProtocolInterestBps(100);

        if (!integration) {
            liquidity.pauseSanctions();
            lending.pauseSanctions();
            flashClaim.pauseSanctions();
            flashSell.pauseSanctions();
        }

        vm.stopPrank();

        vm.label(address(0), "NULL !!!!! ");
    }

    function logBalances(address account) public {
        console.log(account, "ETH", account.balance);
        console.log(account, "DAI", daiToken.balanceOf(account));
        console.log(account, "cETH", liquidity.getCAssetBalance(account, address(cEtherToken)));
        console.log(account, "cDAI", liquidity.getCAssetBalance(account, address(cDAIToken)));
        console.log(
            account,
            "cETH -> ETH",
            liquidity.cAssetAmountToAssetAmount(
                address(cEtherToken),
                liquidity.getCAssetBalance(account, address(cEtherToken))
            )
        );
        console.log(
            account,
            "cDAI -> DAI",
            liquidity.cAssetAmountToAssetAmount(
                address(cDAIToken),
                liquidity.getCAssetBalance(account, address(cDAIToken))
            )
        );
    }
}
