//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IOffersEvents.sol";
import "./IOffersStructs.sol";
import "./IOffersAdmin.sol";
import "../lending/ILendingStructs.sol";


/// @title The Offers interface for Nifty Apes
///        This interface is intended to be used for interacting with offers on the protocol.
interface IOffers is IOffersEvents, IOffersStructs, IOffersAdmin, ILendingStructs {
    /// @notice Returns a loan aution identified by a given nft.
    /// @param nftContractAddress The address of the NFT collection
    /// @param nftId The id of a specified NFT
    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory auction);

    /// @notice Returns an EIP712 standard compatiable hash for a given offer
    ///         This hash can be signed to create a valid offer.
    /// @param offer The offer to compute the hash for
    function getOfferHash(Offer memory offer) external view returns (bytes32);

    /// @notice Returns the signer of an offer or throws an error.
    /// @param offer The offer to use for retrieving the signer
    /// @param signature The signature to use for retrieving the signer
    function getOfferSigner(Offer memory offer, bytes memory signature) external returns (address);

    /// @notice Returns true if a given signature has been revoked otherwise false
    /// @param signature The signature to check
    function getOfferSignatureStatus(bytes calldata signature) external view returns (bool status);

    /// @notice Withdraw a given offer
    ///         Calling this method allows users to withdraw a given offer by cancelling their signature on chain
    /// @param offer The offer to withdraw
    /// @param signature The signature of the offer
    function withdrawOfferSignature(Offer memory offer, bytes calldata signature) external;

    /// @notice Returns an offer from the on-chain offer books
    /// @param nftContractAddress The address of the NFT collection
    /// @param nftId The id of the specified NFT
    /// @param offerHash The hash of all parameters in an offer
    /// @param floorTerm Indicates whether this is a floor or individual NFT offer.
    function getOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external view returns (Offer memory offer);

    /// @notice Creates an offer on the on chain offer book
    /// @param offer The details of offer
    function createOffer(Offer calldata offer) external returns (bytes32);

    /// @notice Removes an offer from the on-chain offer book
    /// @param nftContractAddress The address of the NFT collection
    /// @param nftId The id of the specified NFT
    /// @param offerHash The hash of all parameters in an offer
    /// @param floorTerm Indicates whether this is a floor or individual NFT offer.
    function removeOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external;

    /// @notice Checks that a signature has not been cancelled/withdrawn on chain
    /// @param signature The signature of the offer
    function requireAvailableSignature(bytes memory signature) external view;

    /// @notice Checks that a signature has a length of 65 bytes
    /// @param signature The signature of the offer
    function requireSignature65(bytes memory signature) external pure;

    /// @notice Checks that a signature has a length of 65 bytes
    /// @param offer The details of the offer
    /// @param signature The signature of the offer
    function markSignatureUsed(Offer memory offer, bytes memory signature) external;
}
