//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emmited by the signature lending part of the protocol.
interface ISigLendingEvents {
    /// @notice Emmited when the associated liquidity contract address is changed
    /// @param oldLendingContractAddress The old liquidity contract address
    /// @param newLendingContractAddress The new liquidity contract address
    event SigLendingXLendingContractAddressUpdated(
        address oldLendingContractAddress,
        address newLendingContractAddress
    );
}
