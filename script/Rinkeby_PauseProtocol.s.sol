pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/niftyapes/liquidity/ILiquidity.sol";
import "../src/interfaces/niftyapes/offers/IOffers.sol";
import "../src/interfaces/niftyapes/lending/ILending.sol";
import "../src/interfaces/niftyapes/sigLending/ISigLending.sol";

contract PauseScript is Script {
    function run() external {
        vm.startBroadcast();

        // Rinkeby Addresses
        address liquidityContract = 0x8bC67d5177dD930CD9c9d3cA6Fc33E4f454f30e4;
        address offersContract = 0x9891589826C0e386009819a9DC82e94656036875;
        address lendingContract = 0xd830dcFC57816aDeB9Bf34A5dA38197810fA8Fd4;
        address sigLendingContract = 0x13066734874c538606e5589eE9BB6BbC3C018fAF;

        // pause contracts
        ILiquidity(liquidityContract).pause();
        IOffers(offersContract).pause();
        ILending(lendingContract).pause();
        ISigLending(sigLendingContract).pause();

        vm.stopBroadcast();
    }
}
