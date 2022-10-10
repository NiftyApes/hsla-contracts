// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../Lending.sol";
import "../../../Liquidity.sol";
import "../../../Offers.sol";
import "../../../SigLending.sol";
import "../../../PurchaseWithFinancing.sol";
import "../../../purchaseWithFinancing/integrations/SeaportPwfIntegration.sol";
import "../../../purchaseWithFinancing/integrations/SudoswapPwfIntegration.sol";
import "./NFTAndERC20Fixtures.sol";
import "../../mock/SeaportMock.sol";
import "../../mock/SudoswapFactoryMock.sol";
import "../../mock/SudoswapRouterMock.sol";
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
    NiftyApesPurchaseWithFinancing purchaseWithFinancing;
    SeaportPwfIntegration seaportPWF;
    SudoswapPwfIntegration sudoswapPWF;
    SeaportMock seaportMock;
    LSSVMPairFactoryMock sudoswapFactoryMock;
    LSSVMRouterMock sudoswapRouterMock;

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant SEAPORT_ADDRESS = 0x00000000006c3852cbEf3e08E8dF289169EdE581;
    address constant SUDOSWAP_FACTORY_ADDRESS = 0xb16c1342E617A5B6E4b631EB114483FDB289c0A4;
    address constant SUDOSWAP_ROUTER_ADDRESS = 0x2B2e8cDA09bBA9660dCA5cB6233787738Ad68329;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);

        if (integration) {
            purchaseWithFinancing = new NiftyApesPurchaseWithFinancing();
            purchaseWithFinancing.initialize();

            seaportPWF = new SeaportPwfIntegration();
            seaportPWF.initialize(address(offers), address(purchaseWithFinancing), SEAPORT_ADDRESS);

            sudoswapPWF = new SudoswapPwfIntegration();
            sudoswapPWF.initialize(address(offers), address(purchaseWithFinancing), SUDOSWAP_FACTORY_ADDRESS, SUDOSWAP_ROUTER_ADDRESS);

        } else {
            seaportMock = new SeaportMock();
            sudoswapFactoryMock = new LSSVMPairFactoryMock();
            sudoswapRouterMock = new LSSVMRouterMock();
            purchaseWithFinancing = new NiftyApesPurchaseWithFinancing();
            seaportPWF = new SeaportPwfIntegration();
            sudoswapPWF = new SudoswapPwfIntegration();
            
            purchaseWithFinancing.initialize();
            seaportPWF.initialize(address(offers), address(purchaseWithFinancing), address(seaportMock));
            sudoswapPWF.initialize(address(offers), address(purchaseWithFinancing), address(sudoswapFactoryMock), address(sudoswapRouterMock));
        }

        liquidity = new NiftyApesLiquidity();
        liquidity.initialize(address(compToken), address(purchaseWithFinancing));

        offers = new NiftyApesOffers();
        offers.initialize(address(liquidity), address(purchaseWithFinancing));

        sigLending = new NiftyApesSigLending();
        sigLending.initialize(address(offers), address(purchaseWithFinancing));

        lending = new NiftyApesLending();
        lending.initialize(
            address(liquidity),
            address(offers),
            address(sigLending),
            address(purchaseWithFinancing)
        );

        sigLending.updateLendingContractAddress(address(lending));

        offers.updateLendingContractAddress(address(lending));
        offers.updateSigLendingContractAddress(address(sigLending));

        liquidity.updateLendingContractAddress(address(lending));

        purchaseWithFinancing.updateLiquidityContractAddress(address(liquidity));
        purchaseWithFinancing.updateOffersContractAddress(address(offers));
        purchaseWithFinancing.updateLendingContractAddress(address(lending));
        purchaseWithFinancing.updateSigLendingContractAddress(address(sigLending));
        seaportPWF.updateOffersContractAddress(address(offers));
        sudoswapPWF.updateOffersContractAddress(address(offers));

        liquidity.setCAssetAddress(ETH_ADDRESS, address(cEtherToken));
        liquidity.setMaxCAssetBalance(address(cEtherToken), ~uint256(0));

        liquidity.setCAssetAddress(address(daiToken), address(cDAIToken));
        liquidity.setMaxCAssetBalance(address(cDAIToken), ~uint256(0));

        lending.updateProtocolInterestBps(100);

        if (!integration) {
            liquidity.pauseSanctions();
            lending.pauseSanctions();
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
