// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";


library OfferManager{
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

    event NewOffer(
        address creator,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address asset,
        uint256 amount,
        uint256 interestRate,
        uint256 duration,
        uint256 expiration,
        bool fixedTerms,
        bool floorTerm
    );

    function getOfferHash(Offer memory offer)
        public
        pure
        returns (bytes32 offerhash)
    {
        return
            // _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        offer.nftContractAddress,
                        offer.nftId,
                        offer.asset,
                        offer.amount,
                        offer.interestRate,
                        offer.duration,
                        offer.expiration,
                        offer.fixedTerms,
                        offer.floorTerm
                    )
                );
            // );
    }

    function getOffer(OfferBook storage offerBook, bytes32 offerHash)
        public
        view
        returns (Offer memory offer)
    {
        offer = offerBook.offers[offerHash];
    }

    function getOfferAtIndex(OfferBook storage offerBook, uint256 index)
        public
        view
        returns (bytes32)
    {
        return offerBook.keys[index];
    }

    function size(OfferBook storage offerBook) public view returns (uint256) {
        return offerBook.keys.length;
    }

    function createOffer(OfferBook storage offerBook, Offer memory offer)
        public
    {
        offer.creator = msg.sender;

        bytes32 offerHash = getOfferHash(offer);
        if (offerBook.inserted[offerHash]) {
            offerBook.offers[offerHash] = offer;
        } else {
            offerBook.inserted[offerHash] = true;
            offerBook.offers[offerHash] = offer;
            offerBook.indexOf[offerHash] = offerBook.keys.length;
            offerBook.keys.push(offerHash);
        }

        emit NewOffer(
            offer.creator,
            offer.nftContractAddress,
            offer.nftId,
            offer.asset,
            offer.amount,
            offer.interestRate,
            offer.duration,
            offer.expiration,
            offer.fixedTerms,
            offer.floorTerm
        );
    }

    function removeOffer(OfferBook storage offerBook, bytes32 offerHash) public {
        Offer storage offer = offerBook.offers[offerHash];

        require(
            msg.sender == offer.creator,
            "msg.sender is not the offer creator"
        );

        if (!offerBook.inserted[offerHash]) {
            return;
        }

        delete offerBook.inserted[offerHash];
        delete offerBook.offers[offerHash];

        uint256 index = offerBook.indexOf[offerHash];
        uint256 lastIndex = offerBook.keys.length - 1;
        bytes32 lastOfferHash = offerBook.keys[lastIndex];

        offerBook.indexOf[lastOfferHash] = index;
        delete offerBook.indexOf[offerHash];

        offerBook.keys[index] = lastOfferHash;
        offerBook.keys.pop();
    }
}
