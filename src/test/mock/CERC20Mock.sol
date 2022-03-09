// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { ICERC20 } from "../../interfaces/compound/ICERC20.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../ErrorReporter.sol";
import "../../Exponential.sol";
import "./ERC20Mock.sol";

contract CERC20Mock is ERC20, ICERC20, Exponential {
    ERC20Mock public underlying;

    bool public transferFromFail;
    bool public transferFail;

    bool public mintFail;
    bool public redeemUnderlyingFail;
    uint256 exchangeRateCurrentValue;

    constructor(ERC20Mock _underlying) ERC20("cUSDC", "cUSD") {
        underlying = _underlying;
        exchangeRateCurrentValue = 1;
    }

    function exchangeRateCurrent() public view returns (uint256) {
        return exchangeRateCurrentValue;
    }

    function mint(uint256 mintAmount) external returns (uint256) {
        if (mintFail) {
            return 1;
        }

        (CarefulMath.MathError mathError, uint256 amountCTokens) = divScalarByExpTruncate(
            mintAmount,
            ExponentialNoError.Exp({ mantissa: exchangeRateCurrent() })
        );

        _mint(msg.sender, amountCTokens);

        underlying.burn(msg.sender, mintAmount);

        return uint256(mathError);
    }

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256) {
        if (redeemUnderlyingFail) {
            return 1;
        }

        (CarefulMath.MathError mathError, uint256 amountCTokens) = divScalarByExpTruncate(
            redeemAmount,
            ExponentialNoError.Exp({ mantissa: exchangeRateCurrent() })
        );

        _burn(msg.sender, amountCTokens);

        underlying.mint(msg.sender, redeemAmount);

        return uint256(mathError);
    }

    function setMintFail(bool _mintFail) external {
        mintFail = _mintFail;
    }

    function setRedeemUnderlyingFail(bool _redeemUnderlyingFail) external {
        redeemUnderlyingFail = _redeemUnderlyingFail;
    }

    function setExchangeRateCurrent(uint256 _exchangeRateCurrent) external {
        exchangeRateCurrentValue = _exchangeRateCurrent;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override(ERC20, IERC20) returns (bool) {
        if (transferFromFail) {
            return false;
        }

        return ERC20.transferFrom(from, to, amount);
    }

    function setTransferFromFail(bool fail) external {
        transferFromFail = fail;
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        override(ERC20, IERC20)
        returns (bool)
    {
        if (transferFail) {
            return false;
        }

        return ERC20.transfer(to, amount);
    }

    function setTransferFail(bool fail) external {
        transferFail = fail;
    }
}
