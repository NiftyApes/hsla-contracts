//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../lending/ILendingStructs.sol";

/// @title Events emitted by the refinancing part of the protocol.
interface IRefinanceEvents {

    /// @notice Emitted when a loan is refinanced
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id
    /// @param loanAuction The loanAuction details
    event Refinance(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        ILendingStructs.LoanAuction loanAuction
    );

    /// @notice Emitted when the associated liquidity contract address is changed
    /// @param oldLiquidityContractAddress The old liquidity contract address
    /// @param newLiquidityContractAddress The new liquidity contract address
    event RefinanceXLiquidityContractAddressUpdated(
        address oldLiquidityContractAddress,
        address newLiquidityContractAddress
    );

    /// @notice Emitted when the associated offers contract address is changed
    /// @param oldOffersContractAddress The old offers contract address
    /// @param newOffersContractAddress The new offers contract address
    event RefinanceXOffersContractAddressUpdated(
        address oldOffersContractAddress,
        address newOffersContractAddress
    );

    /// @notice Emitted when the associated lending contract address is changed
    /// @param oldLendingContractAddress The old lending contract address
    /// @param newLendingContractAddress The new lending contract address
    event RefinanceXLendingContractAddressUpdated(
        address oldLendingContractAddress,
        address newLendingContractAddress
    );

    /// @notice Emitted when the associated signature lending contract address is changed
    /// @param oldSigLendingContractAddress The old lending contract address
    /// @param newSigLendingContractAddress The new lending contract address
    event RefinanceXSigLendingContractAddressUpdated(
        address oldSigLendingContractAddress,
        address newSigLendingContractAddress
    );

    /// @notice Emitted when sanctions checks are paused
    event RefinanceSanctionsPaused();

    /// @notice Emitted when sanctions checks are unpaused
    event RefinanceSanctionsUnpaused();
}
