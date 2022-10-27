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

    /// @notice Emitted when the address for OpenseaZone is changed
    /// @param oldOpenseaZone The old OpenseaZone
    /// @param newOpenseaZone The new OpenseaZone
    event OpenseaZoneUpdated(
        address oldOpenseaZone,
        address newOpenseaZone
    );

    /// @notice Emitted when the address for OpenseaFeeRecepient is changed
    /// @param oldOpenseaFeeRecepient The old OpenseaFeeRecepient
    /// @param newOpenseaFeeRecepient The new OpenseaFeeRecepient
    event OpenseaFeeRecepientUpdated(
        address oldOpenseaFeeRecepient,
        address newOpenseaFeeRecepient
    );

    /// @notice Emitted when the OpenseaZoneHash is changed
    /// @param oldOpenseaZoneHash The old OpenseaZoneHash
    /// @param newOpenseaZoneHash The new OpenseaZoneHash
    event OpenseaZoneHashUpdated(
        bytes32 oldOpenseaZoneHash,
        bytes32 newOpenseaZoneHash
    );

    /// @notice Emitted when OpenseaConduitKey is changed
    /// @param oldOpenseaConduitKey The old OpenseaConduitKey
    /// @param newOpenseaConduitKey The new OpenseaConduitKey
    event OpenseaConduitKeyUpdated(
        bytes32 oldOpenseaConduitKey,
        bytes32 newOpenseaConduitKey
    );

    /// @notice Emitted when sanctions checks are paused
    event SellOnSeaportSanctionsPaused();

    /// @notice Emitted when sanctions checks are unpaused
    event SellOnSeaportSanctionsUnpaused();
}
