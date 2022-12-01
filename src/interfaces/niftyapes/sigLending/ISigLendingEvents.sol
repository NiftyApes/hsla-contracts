//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emitted by the signature lending part of the protocol.
interface ISigLendingEvents {
    /// @notice Emitted when the associated liquidity contract address is changed
    /// @param oldLendingContractAddress The old liquidity contract address
    /// @param newLendingContractAddress The new liquidity contract address
    event SigLendingXLendingContractAddressUpdated(
        address oldLendingContractAddress,
        address newLendingContractAddress
    );

    /// @notice Emitted when the associated refinance contract address is changed
    /// @param oldRefinanceContractAddress The old refinance contract address
    /// @param newRefinanceContractAddress The new refinance contract address
    event SigLendingXRefinanceContractAddressUpdated(
        address oldRefinanceContractAddress,
        address newRefinanceContractAddress
    );
}
