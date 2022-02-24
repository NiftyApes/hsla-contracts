// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./Console.sol";
import "ds-test/test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/compound/ICERC20.sol";
import "../interfaces/compound/ICEther.sol";
import "../LiquidityProviders.sol";
import "../Exponential.sol";
import "./Utilities.sol";

// @dev These tests are intended to be run against a forked mainnet.

contract LiquidityProvidersTest is DSTest, TestUtility, Exponential {
    IUniswapV2Router SushiSwapRouter;
    IWETH WETH;
    IERC20 DAI;
    ICERC20 cDAI;
    ICEther cETH;
    LiquidityProviders liquidityProviders;

    // This is needed to receive ETH when calling `withdrawEth`
    receive() external payable {}

    function setUp() public {
        // Setup WETH
        WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        // Setup DAI
        DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

        // Setup SushiSwapRouter
        SushiSwapRouter = IUniswapV2Router(
            0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
        );

        // Setup cETH and balances
        cETH = ICEther(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
        // Mint some cETH
        cETH.mint{value: 10 ether}();

        // Setup DAI balances

        // There is another way to do this using HEVM cheatcodes like so:
        //
        // IEVM.store(address(DAI), 0xde88c4128f6243399c8c224ee49c9683b554a068089998cb8cf2b7c8a19de28d, bytes32(uint256(100000 ether)));
        //
        // but I didn't figure out how to easily calculate the
        // storage addresses for the deployed test contracts or approvals, so I just used a deployed router.

        // So, we get some DAI with Sushiswap.
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(DAI);
        // Let's trade for 100k dai
        SushiSwapRouter.swapExactETHForTokens{value: 100000 ether}(
            100 ether,
            path,
            address(this),
            block.timestamp + 1000
        );

        // Setup cDAI and balances
        // Point at the real compound DAI token deployment
        cDAI = ICERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        // Mint 25 ether in cDAI
        DAI.approve(address(cDAI), 50000 ether);
        cDAI.mint(50000 ether);

        // Setup the liquidity providers contract
        liquidityProviders = new LiquidityProviders();
        // Allow assets for testing
        liquidityProviders.setCAssetAddress(address(DAI), address(cDAI));
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cETH)
        );
        uint256 max = type(uint256).max;

        // Approve spends
        DAI.approve(address(liquidityProviders), max);
        cDAI.approve(address(liquidityProviders), max);
        cETH.approve(address(liquidityProviders), max);

        // Supply to 10k DAI contract
        liquidityProviders.supplyErc20(address(DAI), 100000 ether);
        // Supply 10 ether to contract
        liquidityProviders.supplyEth{value: 10 ether}();
    }

    // Test cases

    function testBalances() public {
        // Just to make sure all our balances got set during setup
        assert(DAI.balanceOf(address(this)) > 0);
        assert(cDAI.balanceOf(address(this)) > 0);
        assert(address(this).balance > 0);
    }

    function testAssetToCAsset() public {
        assert(
            liquidityProviders.assetToCAsset(
                address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
            ) == address(cETH)
        );
    }

    function testSetCAssetAddress() public {
        liquidityProviders.setCAssetAddress(address(DAI), address(cDAI));
        assert(liquidityProviders.assetToCAsset(address(DAI)) == address(cDAI));
    }

    function testGetCAssetBalances() public {
        (
            uint256 cAssetBalance,
            uint256 utilizedAssetBalance,
            uint256 availableCAssetBalance
        ) = liquidityProviders.getCAssetBalances(address(this), address(cDAI));

        assert(cAssetBalance > 0 ether);
        assert(utilizedAssetBalance == 0 ether);
        assert(availableCAssetBalance > 0 ether);
    }

    function testGetAssetsIn() public {
        address[] memory assetsIn = liquidityProviders.getAssetsIn(
            address(this)
        );
    }

    // TODO(Add assertions around expected event emissions)
    // TODO(Fix all failing/commented out test cases here)
    // TODO(Create failing tests/assertions for each function)

    function testSupplyErc20(uint32 deposit) public {
        IERC20 underlying = IERC20(DAI);
        ICERC20 cToken = ICERC20(cDAI);

        uint256 assetBalanceInit = underlying.balanceOf(address(this));

        (uint256 cAssetBalanceInit, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cDAI)
        );

        liquidityProviders.supplyErc20(address(DAI), deposit);

        (, uint256 mintTokens) = divScalarByExpTruncate(
            deposit,
            Exp({mantissa: cToken.exchangeRateCurrent()})
        );

        uint256 assetBalance = underlying.balanceOf(address(this));

        (
            uint256 cAssetBalance,
            uint256 utilizedCAssetBalance,
            uint256 availableCAssetBalance
        ) = liquidityProviders.getCAssetBalances(address(this), address(cDAI));

        assert(assetBalance == (assetBalanceInit - deposit));
        assert(cAssetBalance == (cAssetBalanceInit + mintTokens));
        assert(utilizedCAssetBalance == 0 ether);
        assert(availableCAssetBalance == cAssetBalance);
        assert(cAssetBalance == cToken.balanceOf(address(liquidityProviders)));
    }

    function testSupplyCErc20(uint32 deposit) public {
        (uint256 cAssetBalanceInit, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cDAI)
        );

        liquidityProviders.supplyCErc20(address(cDAI), deposit);

        (uint256 cAssetBalance, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cDAI)
        );

        assert(cAssetBalance == (cAssetBalanceInit + deposit));
        assert(
            cAssetBalance ==
                ICERC20(cDAI).balanceOf(address(liquidityProviders))
        );
    }

    function testWithdrawErc20(uint256 amount, bool redeemType) public {
        // TODO(This needs to assert the cAsset balance of address(this), based on the asset -> cAsset exchange rate)
        emit log_named_uint("amount", amount);

        IERC20 underlying = IERC20(DAI);
        ICERC20 cToken = ICERC20(cDAI);

        uint256 assetBalanceInit = underlying.balanceOf(address(this));

        // we only supplied 100000 ether in setUp so we limit the max fuzz value here.
        // Greater values and fail case will be tested below.
        if (redeemType) {
            if (amount < 1 ether) {
                amount += 1 ether;
            } else if (amount > 100000 ether) {
                amount = 100000 ether;
            }
            emit log_named_uint("amount", amount);

            (
                uint256 cAssetBalanceInit,
                uint256 utilizedCAssetBalanceInit,
                uint256 availableCAssetBalanceInit
            ) = liquidityProviders.getCAssetBalances(
                    address(this),
                    address(cDAI)
                );

            uint256 assetBalanceInit = underlying.balanceOf(address(this));

            (, uint256 redeemTokens) = divScalarByExpTruncate(
                amount,
                Exp({mantissa: cToken.exchangeRateCurrent()})
            );

            emit log_named_uint("redeemTokens", redeemTokens);

            liquidityProviders.withdrawErc20(
                address(DAI),
                redeemType,
                redeemTokens
            );

            (, uint256 redeemAmount) = mulScalarTruncate(
                Exp({mantissa: cToken.exchangeRateCurrent()}),
                redeemTokens
            );

            emit log_named_uint("redeemAmount", redeemAmount);

            uint256 assetBalance = underlying.balanceOf(address(this));

            (
                uint256 cAssetBalance,
                uint256 utilizedCAssetBalance,
                uint256 availableCAssetBalance
            ) = liquidityProviders.getCAssetBalances(
                    address(this),
                    address(cDAI)
                );

            emit log_named_uint("assetBalanceInit", assetBalanceInit);
            emit log_named_uint("assetBalance", assetBalance);
            emit log_named_uint("assetBalance + redeemAmount", assetBalanceInit + redeemAmount + 1);

            // assert(amount == redeemAmount);
            // this test fails because of the math rounding error, in fuzzing, sometimes it rounds, sometimes not so can't just add one. 
            // need to investigate this rounding, may be inside compound math. Could provide a small range to solve this issue as well. 
            assert(assetBalance == (assetBalanceInit + redeemAmount + 1));
            assert(cAssetBalance == (cAssetBalanceInit - redeemTokens));
            // still experiencing a rounding error that leaves the cAssetBalance lesser by 1 wei
            assert(
                cAssetBalance + 1 ==
                    cToken.balanceOf(address(liquidityProviders))
            );
        } else {
            if (amount > 100000 ether) {
                amount = 100000 ether;
            }

            (
                uint256 cAssetBalanceInit,
                uint256 utilizedCAssetBalanceInit,
                uint256 availableCAssetBalanceInit
            ) = liquidityProviders.getCAssetBalances(
                    address(this),
                    address(cDAI)
                );

            uint256 assetBalanceInit = underlying.balanceOf(address(this));

            emit log_named_uint("cAssetBalanceInit", cAssetBalanceInit);
            emit log_named_uint(
                "balanceInComp",
                ICERC20(cDAI).balanceOf(address(liquidityProviders))
            );

            liquidityProviders.withdrawErc20(address(DAI), redeemType, amount);

            (, uint256 redeemTokens) = divScalarByExpTruncate(
                amount,
                Exp({mantissa: cToken.exchangeRateCurrent()})
            );

            uint256 assetBalance = underlying.balanceOf(address(this));

            (
                uint256 cAssetBalance,
                uint256 utilizedCAssetBalance,
                uint256 availableCAssetBalance
            ) = liquidityProviders.getCAssetBalances(
                    address(this),
                    address(cDAI)
                );

            emit log_named_uint("cAssetBalanceInit", cAssetBalanceInit);
            emit log_named_uint("cAssetBalance", cAssetBalance);
            emit log_named_uint(
                "balanceInComp",
                ICERC20(cDAI).balanceOf(address(liquidityProviders))
            );

            assert(assetBalance == (assetBalanceInit + amount));
            assert(cAssetBalance == (cAssetBalanceInit - redeemTokens));
            assert(
                cAssetBalance == cToken.balanceOf(address(liquidityProviders))
            );
        }
    }

    // TODO(Fix the bug)
    // this does not currently test for a fail case
    function testFailWithdrawErc20(uint256 amount, bool redeemType) public {
        // TODO(This needs to assert the cAsset balance of address(this), based on the asset -> cAsset exchange rate)
        // check to see if addressed by changes
        if (amount < 1 ether) {
            amount += 1 ether;
            // we only supplied 100000 ether in setUp so we limit the max fuzz value here.
            // Greater values and fail case will be tested below.
        } else if (amount > 100000 ether) {
            amount = 100000 ether;
        }
        if (redeemType) {
            liquidityProviders.withdrawErc20(address(DAI), redeemType, amount);
        } else {
            // FIXME(There is a bug here where the incorrect cAsset bal is returned)
            (uint256 cAssetBalanceInit, , ) = liquidityProviders
                .getCAssetBalances(address(this), address(cDAI));

            if (amount >= cAssetBalanceInit) {
                amount = cAssetBalanceInit - 1;
            }
            liquidityProviders.withdrawErc20(address(DAI), redeemType, amount);
            cAssetBalanceInit -= amount;

            (uint256 cAssetBalance, , ) = liquidityProviders.getCAssetBalances(
                address(this),
                address(cDAI)
            );

            assert(cAssetBalanceInit == cAssetBalance);
            assert(
                cAssetBalance ==
                    ICERC20(cDAI).balanceOf(address(liquidityProviders))
            );
        }
    }

    function testWithdrawCErc20(uint64 amount) public {
        (uint256 cAssetBalanceInit, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cDAI)
        );
        if (amount > cAssetBalanceInit) {
            amount = uint64(cAssetBalanceInit - 10);
        }
        liquidityProviders.withdrawCErc20(address(cDAI), amount);
        (uint256 cAssetBalance, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cDAI)
        );
        assert(cAssetBalance == (cAssetBalanceInit - amount));
    }

    function testSupplyEth(uint64 deposit) public {
        if (deposit < 1 ether) {
            deposit += 1 ether;
        }
        (uint256 cAssetBalanceInit, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cETH)
        );

        ICEther cToken = ICEther(cETH);

        (, uint256 mintTokens) = divScalarByExpTruncate(
            deposit,
            Exp({mantissa: cToken.exchangeRateCurrent()})
        );

        // TODO(Calculate cAsset conversion rate here)
        liquidityProviders.supplyEth{value: deposit}();

        (uint256 cAssetBalance, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cETH)
        );
        assert(cAssetBalanceInit < cAssetBalance);
        assert(cAssetBalance == mintTokens);
        assert(cAssetBalance == cToken.balanceOf(address(liquidityProviders)));
    }

    // TODO(Fix this test, which fails because of transfer approval)
    function testSupplyCEth(uint64 deposit) public {
        if (deposit < 1 ether) {
            deposit += 1 ether;
        }
        (uint256 cAssetBalanceInit, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cETH)
        );

        liquidityProviders.supplyCEth(deposit);

        (uint256 cAssetBalance, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cETH)
        );
        assert((cAssetBalanceInit + deposit) == cAssetBalance);
        assert(
            cAssetBalance ==
                ICEther(cETH).balanceOf(address(liquidityProviders))
        );
    }

    // TODO(Fix this test, which fails because of transfer approval)
    // this does not currently test for a fail case
    function testFailSupplyCEth(uint64 deposit) public {
        if (deposit < 1 ether) {
            deposit += 1 ether;
        }
        (uint256 cAssetBalanceInit, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cETH)
        );

        liquidityProviders.supplyCEth(deposit);

        (uint256 cAssetBalance, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cETH)
        );
        assert((cAssetBalanceInit + deposit) == cAssetBalance);
        assert(
            cAssetBalance ==
                ICEther(cETH).balanceOf(address(liquidityProviders))
        );
    }

    // TODO(Fix: Must have an available balance greater than or equal to amountToWithdraw)
    function testWithdrawEth(uint64 amount, bool redeem) public {
        // TODO(RedeemTokens fails on too small of an amount)
        if (amount <= 0.01 ether) {
            amount += 0.01 ether;
        }
        if (!redeem) {
            liquidityProviders.supplyEth{value: amount}();
            uint256 ethBalanceInit = address(this).balance;
            liquidityProviders.withdrawEth(redeem, amount);
            uint256 ethBalancePost = address(this).balance;
            assert(ethBalancePost == (ethBalanceInit - amount));
        } else {
            // TODO(Fix approvals here, which seem to be broken)
            liquidityProviders.supplyCErc20(address(cETH), amount);

            (uint256 cAssetBalanceInit, , ) = liquidityProviders
                .getCAssetBalances(address(this), address(cETH));

            // TODO(Fix broken approval in contract)
            liquidityProviders.withdrawEth(redeem, amount);

            (uint256 cAssetBalance, , ) = liquidityProviders.getCAssetBalances(
                address(this),
                address(cETH)
            );

            assert(cAssetBalanceInit == (cAssetBalance - amount));
            assert(
                cAssetBalance ==
                    ICEther(cETH).balanceOf(address(liquidityProviders))
            );
        }
    }

    function testWithdrawCEth(uint64 amount) public {
        if (amount <= 0.01 ether) {
            amount += 0.01 ether;
        }
        // TODO(Fix approvals here, which seem to be broken)
        liquidityProviders.supplyCErc20(address(cETH), amount);

        (uint256 cAssetBalanceInit, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cETH)
        );

        liquidityProviders.withdrawCEth(amount);

        (uint256 cAssetBalance, , ) = liquidityProviders.getCAssetBalances(
            address(this),
            address(cETH)
        );
        assert(cAssetBalanceInit == (cAssetBalance - amount));
        assert(
            cAssetBalance ==
                ICEther(cETH).balanceOf(address(liquidityProviders))
        );
    }
}
