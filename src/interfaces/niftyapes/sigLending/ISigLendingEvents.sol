//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Events emmited by the signature lending part of the protocol.
interface ILendingEvents {
    /// @notice Emmited when the associated offers contract address is changed
    /// @param oldOffersContractAdress The old offers contract address
    /// @param newOffersContractAdress The new offers contract address
    event SigLendingXOffersContractAddressUpdated(
        address oldOffersContractAdress,
        address newOffersContractAdress
    );

    /// @notice Emmited when the associated liquidity contract address is changed
    /// @param oldLiquidityContractAdress The old liquidity contract address
    /// @param newLiquidityContractAdress The new liquidity contract address
    event SigLendingXLiquidityContractAddressUpdated(
        address oldLiquidityContractAdress,
        address newLiquidityContractAdress
    );
}
