//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../lending/ILendingStructs.sol";

/// @title Events emitted by the lending part of the protocol.
interface IPurchaseWithFinancingEvents {
    /// @notice Emitted when a OpenSea new loan is executed
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    /// @param loanAuction The loan auction details
    event LoanExecutedSeaport(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        ILendingStructs.LoanAuction loanAuction
    );

    /// @notice Emitted when a Sudoswap new loan is executed
    /// @param nftContractAddress The nft contract address
    /// @param nftId The nft id, this field can be meaningless if the offer is a floor term offer
    /// @param loanAuction TThe loan auction details
    event LoanExecutedSudoswap(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        ILendingStructs.LoanAuction loanAuction
    );

    /// @notice Emitted when the associated liquidity contract address is changed
    /// @param oldLiquidityContractAddress The old liquidity contract address
    /// @param newLiquidityContractAddress The new liquidity contract address
    event PurchaseWithFinancingXLiquidityContractAddressUpdated(
        address oldLiquidityContractAddress,
        address newLiquidityContractAddress
    );

    /// @notice Emitted when the associated offers contract address is changed
    /// @param oldOffersContractAddress The old offers contract address
    /// @param newOffersContractAddress The new offers contract address
    event PurchaseWithFinancingXOffersContractAddressUpdated(
        address oldOffersContractAddress,
        address newOffersContractAddress
    );

    /// @notice Emitted when the associated lending contract address is changed
    /// @param oldLendingContractAddress The old lending contract address
    /// @param newLendingContractAddress The new lending contract address
    event PurchaseWithFinancingXLendingContractAddressUpdated(
        address oldLendingContractAddress,
        address newLendingContractAddress
    );

    /// @notice Emitted when the associated signature lending contract address is changed
    /// @param oldSigLendingContractAddress The old lending contract address
    /// @param newSigLendingContractAddress The new lending contract address
    event PurchaseWithFinancingXSigLendingContractAddressUpdated(
        address oldSigLendingContractAddress,
        address newSigLendingContractAddress
    );

    /// @notice Emitted when the address for Seaport is changed
    /// @param newSeaportContractAddress The new address of the Seaport Contract
    event SeaportContractAddressUpdated(address newSeaportContractAddress);

    /// @notice Emitted when the address for Sudoswap Factory contract address is changed
    /// @param newSudoswapFactoryContractAddress The new address of the Sudoswap Factory contract
    event SudoswapFactoryContractAddressUpdated(address newSudoswapFactoryContractAddress);

    /// @notice Emitted when the address for Sudoswap Router contract address is changed
    /// @param newSudoswapRouterContractAddress The new address of the Sudoswap Router contract
    event SudoswapRouterContractAddressUpdated(address newSudoswapRouterContractAddress);

    /// @notice Emitted when sanctions checks are paused
    event PurchaseWithFinancingSanctionsPaused();

    /// @notice Emitted when sanctions checks are unpaused
    event PurchaseWithFinancingSanctionsUnpaused();
}
