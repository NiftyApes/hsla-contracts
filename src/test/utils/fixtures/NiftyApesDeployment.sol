// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../Lending.sol";
import "../../../Liquidity.sol";
import "../../../Offers.sol";
import "../../../SigLending.sol";
import "../../../PurchaseWithFinancing.sol";
import "./NFTAndERC20Fixtures.sol";
import "../../mock/SeaportMock.sol";

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
    SeaportMock seaportMock;

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);
        seaportMock = new SeaportMock();
        purchaseWithFinancing = new NiftyApesPurchaseWithFinancing();
        purchaseWithFinancing.initialize(address(seaportMock));
        seaportMock.approve(address(purchaseWithFinancing));

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
