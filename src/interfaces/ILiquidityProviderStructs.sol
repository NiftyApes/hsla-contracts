//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./ILiquidityProviderEvents.sol";

interface ILiquidityProviderStructs is ILiquidityProviderEvents {
    struct Balance {
        uint256 cAssetBalance;
    }
}
