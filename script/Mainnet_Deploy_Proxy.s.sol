pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "@openzeppelin-norm/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin-norm/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployNiftyApesScript is Script {
    function run() external {
        ProxyAdmin lendingProxyAdmin;
        ProxyAdmin offersProxyAdmin;
        ProxyAdmin liquidityProxyAdmin;
        ProxyAdmin sigLendingProxyAdmin;
        TransparentUpgradeableProxy lendingProxy;
        TransparentUpgradeableProxy offersProxy;
        TransparentUpgradeableProxy liquidityProxy;
        TransparentUpgradeableProxy sigLendingProxy;

        address mainnetMultisigAddress = 0xbe9B799D066A51F77d353Fc72e832f3803789362;

        // Deployed Mainnet Implementation Addresses
        address lending = 0xbe9B799D066A51F77d353Fc72e832f3803789362;
        address offers = 0xbe9B799D066A51F77d353Fc72e832f3803789362;
        address liquidity = 0xbe9B799D066A51F77d353Fc72e832f3803789362;
        address sigLending = 0xbe9B799D066A51F77d353Fc72e832f3803789362;

        vm.startBroadcast();

        lendingProxyAdmin = new ProxyAdmin();
        offersProxyAdmin = new ProxyAdmin();
        liquidityProxyAdmin = new ProxyAdmin();
        sigLendingProxyAdmin = new ProxyAdmin();

        lendingProxy = new TransparentUpgradeableProxy(
            lending,
            address(lendingProxyAdmin),
            bytes("")
        );
        offersProxy = new TransparentUpgradeableProxy(offers, address(offersProxyAdmin), bytes(""));
        liquidityProxy = new TransparentUpgradeableProxy(
            liquidity,
            address(liquidityProxyAdmin),
            bytes("")
        );

        sigLendingProxy = new TransparentUpgradeableProxy(
            sigLending,
            address(sigLendingProxyAdmin),
            bytes("")
        );

        lendingProxyAdmin.changeProxyAdmin(lendingProxy, mainnetMultisigAddress);
        offersProxyAdmin.changeProxyAdmin(offersProxy, mainnetMultisigAddress);
        liquidityProxyAdmin.changeProxyAdmin(liquidityProxy, mainnetMultisigAddress);
        sigLendingProxyAdmin.changeProxyAdmin(sigLendingProxy, mainnetMultisigAddress);

        vm.stopBroadcast();
    }
}
