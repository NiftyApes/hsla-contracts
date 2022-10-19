//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emitted by the FlashSell.
interface IFlashSellEvents {
    /// @notice Emitted when a the 
    /// @param nftContractAddress The nft contract address
    /// @param nftId The tokenId of the NFT which was put as collateral
    /// @param nftReceiver The contract which receives the NFT to execute sale
    event FlashSell(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address indexed nftReceiver
    );

    /// @notice Emitted when the associated lending contract address is changed
    /// @param oldLendingContractAddress The old lending contract address
    /// @param newLendingContractAddress The new lending contract address
    event FlashSellXLendingContractAddressUpdated(
        address oldLendingContractAddress,
        address newLendingContractAddress
    );

    /// @notice Emitted when sanctions checks are paused
    event FlashSellSanctionsPaused();

    /// @notice Emitted when sanctions checks are unpaused
    event FlashSellSanctionsUnpaused();
}