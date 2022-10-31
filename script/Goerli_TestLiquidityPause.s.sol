pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/niftyapes/liquidity/ILiquidity.sol";
import "../src/interfaces/niftyapes/offers/IOffers.sol";
import "../src/interfaces/niftyapes/lending/ILending.sol";
import "../src/interfaces/niftyapes/sigLending/ISigLending.sol";

contract TestLiquidityPauseScript is Script {
    function run() external {
        vm.startBroadcast();

        // Goerli Addresses
        address liquidityContract = 0x606f95374FD79B4b6057eb8bBFA54EfdEA039E67;

        // attempt to supply liquidity
        ILiquidity(liquidityContract).supplyEth{ value: 0.01 ether }();

        vm.stopBroadcast();
    }
}
