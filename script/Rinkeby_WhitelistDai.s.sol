pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/niftyapes/liquidity/ILiquidity.sol";

contract WhitelistDaiScript is Script {
    function run() external {
        vm.startBroadcast();

        // Rinkeby Addresses
        address dai = 0x95b58a6Bff3D14B7DB2f5cb5F0Ad413DC2940658;
        address cDai = 0x6D7F0754FFeb405d23C51CE938289d4835bE3b14;
        address liquidityContract = 0x8bC67d5177dD930CD9c9d3cA6Fc33E4f454f30e4;

        // DAI
        ILiquidity(liquidityContract).setCAssetAddress(dai, cDai);

        uint256 cDaiAmount = ILiquidity(liquidityContract).assetAmountToCAssetAmount(dai, 500000);

        ILiquidity(liquidityContract).setMaxCAssetBalance(cDai, cDaiAmount);

        vm.stopBroadcast();
    }
}
