// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

library OfferManager {
    // This will be hashed to a unique offer
    struct Offer {
        // Offer creator
        address creator;
        // Offer type bid/ask is computed with the creator and nft owner
        // Would it be useful to have an enum here?
        // offer NFT contract address
        address nftContractAddress;
        // offer NFT ID
        uint256 nftId; // ignored if floorTerm is true
        // offer asset type
        address asset;
        // offer loan amount
        uint256 amount;
        // offer interest rate
        uint256 interestRate;
        // offer loan duration
        uint256 duration;
        // offer expiration
        uint256 expiration;
        // is loan offer fixed terms or open for perpetual auction
        bool fixedTerms;
        // is offer for single NFT or for every NFT in a collection
        bool floorTerm;
    }

    // Iterable mapping from address to uint;
    struct OfferBook {
        bytes32[] keys;
        mapping(bytes32 => Offer) offers;
        mapping(bytes32 => uint256) indexOf;
        mapping(bytes32 => bool) inserted;
    }

    function get(OfferBook storage map, bytes32 key)
        public
        view
        returns (Offer memory offer)
    {
        offer = map.offers[key];
    }

    function getKeyAtIndex(OfferBook storage map, uint256 index)
        public
        view
        returns (bytes32)
    {
        return map.keys[index];
    }

    function size(OfferBook storage map) public view returns (uint256) {
        return map.keys.length;
    }

    function set(
        OfferBook storage map,
        bytes32 key,
        Offer memory val
    ) public {
        if (map.inserted[key]) {
            map.offers[key] = val;
        } else {
            map.inserted[key] = true;
            map.offers[key] = val;
            map.indexOf[key] = map.keys.length;
            map.keys.push(key);
        }
    }

    function remove(OfferBook storage map, bytes32 key) public {
        Offer storage offer = map.offers[key];

        require(msg.sender == offer.creator || msg.sender == address(this), "msg.sender is not the offer creator");

        if (!map.inserted[key]) {
            return;
        }

        delete map.inserted[key];
        delete map.offers[key];

        uint256 index = map.indexOf[key];
        uint256 lastIndex = map.keys.length - 1;
        bytes32 lastKey = map.keys[lastIndex];

        map.indexOf[lastKey] = index;
        delete map.indexOf[key];

        map.keys[index] = lastKey;
        map.keys.pop();
    }
}
