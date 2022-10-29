pragma solidity ^0.8.13;

import "@openzeppelin-norm/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin-norm/contracts/proxy/transparent/ProxyAdmin.sol";

import "../../../interfaces/niftyapes/lending/ILending.sol";
import "../../../interfaces/niftyapes/offers/IOffers.sol";
import "../../../interfaces/niftyapes/liquidity/ILiquidity.sol";
import "../../../interfaces/niftyapes/sigLending/ISigLending.sol";

import "./NiftyApesDeployment.sol";

import "forge-std/Test.sol";

contract DeployProxy is Test, NiftyApesDeployment {
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

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);

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
        liquidity.initialize(address(compToken));
        offers.initialize(address(liquidity));
        sigLending.initialize(address(offers));
        lending.initialize(address(liquidity), address(offers), address(sigLending));

        // associate proxies
        liquidity.updateLendingContractAddress(address(lending));

        offers.updateLendingContractAddress(address(lending));
        offers.updateSigLendingContractAddress(address(sigLending));

        sigLending.updateLendingContractAddress(address(lending));

        // set max balances
        liquidity.setCAssetAddress(ETH_ADDRESS, address(cEtherToken));
        liquidity.setMaxCAssetBalance(address(cEtherToken), ~uint256(0));

        liquidity.setCAssetAddress(address(daiToken), address(cDAIToken));
        liquidity.setMaxCAssetBalance(address(cDAIToken), ~uint256(0));

        // update protocol interest
        lending.updateProtocolInterestBps(100);
        lending.updateDefaultRefinancePremiumBps(25);

        if (!integration) {
            liquidity.pauseSanctions();
            lending.pauseSanctions();
        }

        vm.stopPrank();
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
