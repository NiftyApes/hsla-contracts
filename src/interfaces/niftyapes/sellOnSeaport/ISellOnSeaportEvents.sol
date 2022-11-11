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

    /// @notice Emitted when the address for FlashSell is changed
    /// @param oldFlashSellContractAddress The old address of the FlashSell Contract
    /// @param newFlashSellContractAddress The new address of the FlashSell Contract
    event SellOnSeaportXFlashSellContractAddressUpdated(
        address oldFlashSellContractAddress,
        address newFlashSellContractAddress
    );

    /// @notice Emitted when the address for Weth contract is changed
    /// @param oldWethContractAddress The old address of the Weth Contract
    /// @param newWethContractAddress The new address of the Weth Contract
    event SellOnSeaportXWethContractAddressUpdated(
        address oldWethContractAddress,
        address newWethContractAddress
    );

    /// @notice Emitted when the address for OpenSeaZone is changed
    /// @param oldOpenSeaZone The old OpenSeaZone
    /// @param newOpenSeaZone The new OpenSeaZone
    event OpenSeaZoneUpdated(
        address oldOpenSeaZone,
        address newOpenSeaZone
    );

    /// @notice Emitted when the address for OpenSeaFeeRecepient is changed
    /// @param oldOpenSeaFeeRecepient The old OpenSeaFeeRecepient
    /// @param newOpenSeaFeeRecepient The new OpenSeaFeeRecepient
    event OpenSeaFeeRecepientUpdated(
        address oldOpenSeaFeeRecepient,
        address newOpenSeaFeeRecepient
    );

    /// @notice Emitted when the OpenSeaZoneHash is changed
    /// @param oldOpenSeaZoneHash The old OpenSeaZoneHash
    /// @param newOpenSeaZoneHash The new OpenSeaZoneHash
    event OpenSeaZoneHashUpdated(
        bytes32 oldOpenSeaZoneHash,
        bytes32 newOpenSeaZoneHash
    );

    /// @notice Emitted when OpenSeaConduitKey is changed
    /// @param oldOpenSeaConduitKey The old OpenSeaConduitKey
    /// @param newOpenSeaConduitKey The new OpenSeaConduitKey
    event OpenSeaConduitKeyUpdated(
        bytes32 oldOpenSeaConduitKey,
        bytes32 newOpenSeaConduitKey
    );

    /// @notice Emitted when OpenSeaConduit is changed
    /// @param oldOpenSeaConduit The old OpenSeaConduit
    /// @param newOpenSeaConduit The new OpenSeaConduit
    event OpenSeaConduitUpdated(
        address oldOpenSeaConduit,
        address newOpenSeaConduit
    );

    /// @notice Emitted when sanctions checks are paused
    event SellOnSeaportSanctionsPaused();

    /// @notice Emitted when sanctions checks are unpaused
    event SellOnSeaportSanctionsUnpaused();
}
