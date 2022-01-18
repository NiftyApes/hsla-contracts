// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IInterestRateModel} from "./IInterestRateModel.sol";

interface ICToken is IERC20 {
    function borrow(uint256) external returns (uint256);

    function totalBorrows() external view returns (uint256);

    function totalFuseFees() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function totalAdminFees() external view returns (uint256);

    function fuseFeeMantissa() external view returns (uint256);

    function adminFeeMantissa() external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function accrualBlockNumber() external view returns (uint256);

    function redeemUnderlying(uint256) external returns (uint256);

    function balanceOfUnderlying(address) external returns (uint256);

    function reserveFactorMantissa() external view returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function interestRateModel() external view returns (IInterestRateModel);

    function initialExchangeRateMantissa() external view returns (uint256);
}
