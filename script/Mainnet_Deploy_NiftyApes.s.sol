pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Liquidity.sol";
import "../src/Offers.sol";
import "../src/SigLending.sol";
import "../src/Lending.sol";
import "../src/FlashClaim.sol";
import "../src/FlashPurchase.sol";
import "../src/FlashSell.sol";
import "../src/Refinance.sol";

contract DeployNiftyApesScript is Script {
    function run() external {
        NiftyApesLending lending;
        NiftyApesOffers offers;
        NiftyApesLiquidity liquidity;
        NiftyApesSigLending sigLending;
        NiftyApesRefinance refinance;
        NiftyApesFlashClaim flashClaim;
        NiftyApesFlashPurchase flashPurchase;
        NiftyApesFlashSell flashSell;
        
        address compContractAddress = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        address mainnetMultisigAddress = 0xbe9B799D066A51F77d353Fc72e832f3803789362;

        vm.startBroadcast();

        flashClaim = new NiftyApesFlashClaim();
        flashClaim.initialize();

        flashPurchase = new NiftyApesFlashPurchase();
        flashPurchase.initialize();

        flashSell = new NiftyApesFlashSell();
        flashSell.initialize();

        refinance = new NiftyApesRefinance();
        refinance.initialize();

        liquidity = new NiftyApesLiquidity();
        liquidity.initialize(address(compContractAddress), address(refinance), address(flashPurchase));

        offers = new NiftyApesOffers();
        offers.initialize(address(liquidity), address(refinance), address(flashPurchase));

        sigLending = new NiftyApesSigLending();
        sigLending.initialize(address(offers), address(flashPurchase));

        lending = new NiftyApesLending();
        lending.initialize(
            address(liquidity),
            address(offers),
            address(sigLending),
            address(refinance),
            address(flashClaim),
            address(flashPurchase),
            address(flashSell)
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

        refinance.updateLendingContractAddress(address(lending));
        refinance.updateLiquidityContractAddress(address(liquidity));
        refinance.updateOffersContractAddress(address(offers));
        refinance.updateSigLendingContractAddress(address(sigLending));

        // Mainnet Addresses
        address daiToken = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address cDAIToken = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
        address ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address cEtherToken = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

        // DAI
        liquidity.setCAssetAddress(daiToken, cDAIToken);

        uint256 cDAIAmount = liquidity.assetAmountToCAssetAmount(daiToken, type(uint256).max);

        liquidity.setMaxCAssetBalance(cDAIToken, cDAIAmount);

        // ETH
        liquidity.setCAssetAddress(ETH_ADDRESS, cEtherToken);

        uint256 cEtherAmount = liquidity.assetAmountToCAssetAmount(ETH_ADDRESS, type(uint256).max);

        liquidity.setMaxCAssetBalance(cEtherToken, cEtherAmount);

        liquidity.transferOwnership(mainnetMultisigAddress);
        lending.transferOwnership(mainnetMultisigAddress);
        offers.transferOwnership(mainnetMultisigAddress);
        sigLending.transferOwnership(mainnetMultisigAddress);
        flashClaim.transferOwnership(mainnetMultisigAddress);
        flashPurchase.transferOwnership(mainnetMultisigAddress);
        flashSell.transferOwnership(mainnetMultisigAddress);
        refinance.transferOwnership(mainnetMultisigAddress);

        vm.stopBroadcast();
    }
}
