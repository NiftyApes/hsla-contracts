//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../lending/ILendingStructs.sol";

/// @title Events emitted by the SellOnSeaport contract
interface ISellOnSeaportEvents {
    /// @notice Emitted when an locked NFT is listed for sale through Seaport
    /// @param nftContractAddress The nft contract address
    /// @param nftId The tokenId of the listed NFT
    /// @param orderHash The hash of the order which listed the NFT
    /// @param loanAuction The loan details at the time of listing
    event ListedOnSeaport(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        bytes32 indexed orderHash,
        ILendingStructs.LoanAuction loanAuction   
    );

    /// @notice Emitted when a seaport NFT listing thorugh NiftyApes is cancelled by the borrower
    /// @param nftContractAddress The nft contract address
    /// @param nftId The tokenId of the listed NFT
    /// @param orderHash The hash of the order which listed the NFT
    /// @param loanAuction The loan details at the time of listing
    event ListingCancelledSeaport(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        bytes32 indexed orderHash,
        ILendingStructs.LoanAuction loanAuction   
    );

    /// @notice Emitted when the associated liquidity contract address is changed
    /// @param oldLiquidityContractAddress The old liquidity contract address
    /// @param newLiquidityContractAddress The new liquidity contract address
    event SellOnSeaportXLiquidityContractAddressUpdated(
        address oldLiquidityContractAddress,
        address newLiquidityContractAddress
    );

    /// @notice Emitted when the associated lending contract address is changed
    /// @param oldLendingContractAddress The old lending contract address
    /// @param newLendingContractAddress The new lending contract address
    event SellOnSeaportXLendingContractAddressUpdated(
        address oldLendingContractAddress,
        address newLendingContractAddress
    );

    /// @notice Emitted when the address for Seaport is changed
    /// @param oldSeaportContractAddress The old address of the Seaport Contract
    /// @param newSeaportContractAddress The new address of the Seaport Contract
    event SellOnSeaportXSeaportContractAddressUpdated(
        address oldSeaportContractAddress,
        address newSeaportContractAddress
    );

    /// @notice Emitted when the address for SeaportZone is changed
    /// @param oldSeaportZone The old SeaportZone
    /// @param newSeaportZone The new SeaportZone
    event SeaportZoneUpdated(
        address oldSeaportZone,
        address newSeaportZone
    );

    /// @notice Emitted when the address for SeaportFeeRecepient is changed
    /// @param oldSeaportFeeRecepient The old SeaportFeeRecepient
    /// @param newSeaportFeeRecepient The new SeaportFeeRecepient
    event SeaportFeeRecepientUpdated(
        address oldSeaportFeeRecepient,
        address newSeaportFeeRecepient
    );

    /// @notice Emitted when the SeaportZoneHash is changed
    /// @param oldSeaportZoneHash The old SeaportZoneHash
    /// @param newSeaportZoneHash The new SeaportZoneHash
    event SeaportZoneHashUpdated(
        bytes32 oldSeaportZoneHash,
        bytes32 newSeaportZoneHash
    );

    /// @notice Emitted when SeaportConduitKey is changed
    /// @param oldSeaportConduitKey The old SeaportConduitKey
    /// @param newSeaportConduitKey The new SeaportConduitKey
    event SeaportConduitKeyUpdated(
        bytes32 oldSeaportConduitKey,
        bytes32 newSeaportConduitKey
    );

    /// @notice Emitted when SeaportConduit is changed
    /// @param oldSeaportConduit The old SeaportConduit
    /// @param newSeaportConduit The new SeaportConduit
    event SeaportConduitUpdated(
        address oldSeaportConduit,
        address newSeaportConduit
    );

    /// @notice Emitted when sanctions checks are paused
    event SellOnSeaportSanctionsPaused();

    /// @notice Emitted when sanctions checks are unpaused
    event SellOnSeaportSanctionsUnpaused();
}
