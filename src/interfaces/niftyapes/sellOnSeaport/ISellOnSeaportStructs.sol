//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ISellOnSeaportStructs {
    struct SeaportListing {
        address nftContractAddress;
        uint256 nftId;
        uint256 listingValue;
    }
}
