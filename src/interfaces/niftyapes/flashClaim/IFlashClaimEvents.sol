//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emitted by the FlashClaim part of the protocol.
interface IFlashClaimEvents {
    /// @notice Emitted when a flashClaim is executed on an NFT
    /// @param nftContractAddress The address of the NFT collection
    /// @param nftId The id of the specified NFT
    /// @param receiverAddress The address of the external contract that will receive and return the nft
    event FlashClaim(address nftContractAddress, uint256 nftId, address receiverAddress);

    /// @notice Emitted when the associated lending contract address is changed
    /// @param oldLendingContractAddress The old lending contract address
    /// @param newLendingContractAddress The new lending contract address
    event FlashClaimXLendingContractAddressUpdated(
        address oldLendingContractAddress,
        address newLendingContractAddress
    );

    /// @notice Emitted when sanctions checks are paused
    event FlashClaimSanctionsPaused();

    /// @notice Emitted when sanctions checks are unpaused
    event FlashClaimSanctionsUnpaused();
}
