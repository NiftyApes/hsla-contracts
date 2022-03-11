pragma solidity ^0.8.11;
//SPDX-License-Identifier: MIT

import "./LibAsset.sol";

library LibOrder {
    struct Order {
        address maker;
        LibAsset.Asset makeAsset;
        address taker;
        LibAsset.Asset takeAsset;
        uint256 salt;
        uint256 start;
        uint256 end;
        bytes4 dataType;
        bytes data;
    }
}
