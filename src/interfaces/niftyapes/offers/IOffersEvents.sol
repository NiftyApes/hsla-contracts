//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IOffersStructs.sol";

/// @title Events emmited by the offers part of the protocol.
interface IOffersEvents {
    /// @notice Emited when a new offer is stored on chain
    /// @param creator The creator of the offer, this can either be a borrower or a lender (check boolean flag in the offer).
    /// @param asset The asset in which the offer is denominated
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    /// @param offer The offer details
    /// @param offerHash The offer hash
    event NewOffer(
        address indexed creator,
        address asset,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        IOffersStructs.Offer offer,
        bytes32 offerHash
    );

    /// @notice Emited when a offer is removed from chain
    /// @param creator The creator of the offer, this can either be a borrower or a lender (check boolean flag in the offer).
    /// @param asset The asset in which the offer is denominated
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    /// @param offer The offer details
    /// @param offerHash The offer hash
    event OfferRemoved(
        address indexed creator,
        address asset,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        IOffersStructs.Offer offer,
        bytes32 offerHash
    );

    /// @notice Emitted when a offer signature gets has been used
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    /// @param offer The offer details
    /// @param signature The signature that has been revoked
    event OfferSignatureUsed(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        IOffersStructs.Offer offer,
        bytes signature
    );

    /// @notice Emmited when the associated lending contract address is changed
    /// @param oldLendingContractAdress The old lending contract address
    /// @param newLendingContractAdress The new lending contract address
    event LendingContractAddressUpdated(
        address oldLendingContractAdress,
        address newLendingContractAdress
    );
}
