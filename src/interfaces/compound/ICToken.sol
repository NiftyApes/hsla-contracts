// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICToken is IERC20 {
    function exchangeRateCurrent() external returns (uint256);
}
