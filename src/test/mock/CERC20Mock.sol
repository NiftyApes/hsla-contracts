// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { ICERC20 } from "../../interfaces/compound/ICERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CERC20Mock is ERC20, ICERC20 {
    ERC20 public underlying;

    constructor(address _underlying) ERC20("cUSDC", "cUSD") {
        underlying = ERC20(_underlying);
    }

    function exchangeRateCurrent() external returns (uint256) {}

    function mint(uint256 mintAmount) external returns (uint256) {}

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256) {}
}
