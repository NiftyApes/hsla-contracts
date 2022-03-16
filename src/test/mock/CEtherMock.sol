// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { ICEther } from "../../interfaces/compound/ICEther.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../../Math.sol";

contract CEtherMock is ERC20, ICEther {
    bool public transferFromFail;
    bool public transferFail;

    bool public mintFail;
    bool public redeemUnderlyingFail;
    uint256 exchangeRateCurrentValue;

    constructor() ERC20("cEth", "cEth") {
        exchangeRateCurrentValue = 1;
    }

    function exchangeRateCurrent() public view returns (uint256) {
        return exchangeRateCurrentValue;
    }

    function mint() external payable {
        if (mintFail) {
            revert("cToken mint");
        }

        uint256 amountCTokens = Math.divScalarByExpTruncate(msg.value, exchangeRateCurrent());

        _mint(msg.sender, amountCTokens);
    }

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256) {
        if (redeemUnderlyingFail) {
            return 1;
        }

        uint256 amountCTokens = Math.divScalarByExpTruncate(redeemAmount, exchangeRateCurrent());

        _burn(msg.sender, amountCTokens);

        Address.sendValue(payable(msg.sender), redeemAmount);

        return 0;
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
