//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../lending/ILendingStructs.sol";

/// @title Events emitted by the financing part of the protocol.
interface IFlashPurchaseEvents {
    /// @notice Emitted when a new loan is executed for the purchase of an NFT
    /// @param nftContractAddress The nft contract address
    /// @param nftId The tokenId of the NFT which was put as collateral
    /// @param financeReceiver The contract which receives finance for the purchase
    /// @param loanAuction The loan details
    event LoanExecutedForPurchase(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address indexed financeReceiver,
        ILendingStructs.LoanAuction loanAuction
    );

    /// @notice Emitted when the associated liquidity contract address is changed
    /// @param oldLiquidityContractAddress The old liquidity contract address
    /// @param newLiquidityContractAddress The new liquidity contract address
    event FlashPurchaseXLiquidityContractAddressUpdated(
        address oldLiquidityContractAddress,
        address newLiquidityContractAddress
    );

    /// @notice Emitted when the associated offers contract address is changed
    /// @param oldOffersContractAddress The old offers contract address
    /// @param newOffersContractAddress The new offers contract address
    event FlashPurchaseXOffersContractAddressUpdated(
        address oldOffersContractAddress,
        address newOffersContractAddress
    );

    /// @notice Emitted when the associated lending contract address is changed
    /// @param oldLendingContractAddress The old lending contract address
    /// @param newLendingContractAddress The new lending contract address
    event FlashPurchaseXLendingContractAddressUpdated(
        address oldLendingContractAddress,
        address newLendingContractAddress
    );

    /// @notice Emitted when the associated signature lending contract address is changed
    /// @param oldSigLendingContractAddress The old lending contract address
    /// @param newSigLendingContractAddress The new lending contract address
    event FlashPurchaseXSigLendingContractAddressUpdated(
        address oldSigLendingContractAddress,
        address newSigLendingContractAddress
    );
    /// @notice Emitted when sanctions checks are paused
    event FlashPurchaseSanctionsPaused();

    /// @notice Emitted when sanctions checks are unpaused
    event FlashPurchaseSanctionsUnpaused();
}
