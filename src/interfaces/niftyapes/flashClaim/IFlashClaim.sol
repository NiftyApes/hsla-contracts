//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IFlashClaimAdmin.sol";
import "./IFlashClaimEvents.sol";

/// @title The FlashClaim interface for NiftyApes
///        This interface is intended to be used for interacting with flashClaim functionality on the protocol
interface IFlashClaim is IFlashClaimAdmin, IFlashClaimEvents {
    /// @notice Returns the address for the associated lending contract
    function lendingContractAddress() external view returns (address);

    /// @notice Allows an nftOwner to claim their nft and perform arbtrary actions (claim airdrops, vote in goverance, etc)
    ///         while maintaining their loan
    /// @param receiver The address of the external contract that will receive and return the nft
    /// @param nftContractAddress The address of the nft collection
    /// @param nftId The id of the specified nft
    /// @param data Arbitrary data structure, intended to contain user-defined parameters
    function flashClaim(
        address receiver,
        address nftContractAddress,
        uint256 nftId,
        bytes calldata data
    ) external;

    function initialize() external;
}
