//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "./IPurchaseWithFinancingAdmin.sol";
import "./IPurchaseWithFinancingEvents.sol";
import "../offers/IOffersStructs.sol";
import "../lending/ILendingStructs.sol";
import "../../seaport/ISeaport.sol";
import "../../sudoswap/ILSSVMPair.sol";

interface IPurchaseWithFinancing is
    IPurchaseWithFinancingAdmin,
    IPurchaseWithFinancingEvents,
    IOffersStructs,
    ILendingStructs
{
    /// @notice Returns the address for the associated liquidity contract
    function liquidityContractAddress() external view returns (address);

    /// @notice Returns the address for the associated offers contract
    function offersContractAddress() external view returns (address);

    /// @notice Returns the address for the associated lending contract
    function lendingContractAddress() external view returns (address);

    /// @notice Returns the address for the associated sigLending contract
    function sigLendingContractAddress() external view returns (address);

    /// @notice Returns the address for the associated seaport contract
    function seaportContractAddress() external view returns (address);

    /// @notice Returns the address for the associated sudoswap router
    function sudoswapRouterContractAddress() external view returns (address);

    /// @notice Returns the address for the associated sudoswap factory
    function sudoswapFactoryContractAddress() external view returns (address);

    /// @notice Allows a user to borrow ETH to purchase NFTs.
    /// @param offerHash Hash of the existing offer in NiftyApes on-chain offerBook
    /// @param floorTerm Determines if this is a floor offer or not.
    /// @param order Seaport parameters the caller is expected to fill out.
    /// @param fulfillerConduitKey Seaport conduit key of the fulfiller
    function purchaseWithFinancingSeaport(
        address nftContractAddress,
        bytes32 offerHash,
        bool floorTerm,
        ISeaport.Order calldata order,
        bytes32 fulfillerConduitKey
    ) external payable;

    /// @notice Allows purchaseWithFinancingSeaport to interact directly with the lending contract
    /// @param offer The details of the loan offer
    /// @param borrower The prospecive borrower on the loan
    /// @param order Seaport parameters the caller is expected to fill out
    /// @param fulfillerConduitKey Seaport conduit key of the fulfiller
    function doPurchaseWithFinancingSeaport(
        Offer memory offer,
        address borrower,
        ISeaport.Order calldata order,
        bytes32 fulfillerConduitKey
    ) external payable;

    /// @notice Allows a user to borrow ETH to purchase NFTs through Sudoswap.
    /// @param offerHash Hash of the existing offer in NiftyApes on-chain offerBook.
    /// @param floorTerm Determines if this is a floor offer or not.
    /// @param lssvmPair Sudoswap nft-token pair pool.
    /// @param nftId Id of the NFT the borrower intends to buy.
    function purchaseWithFinancingSudoswap(
        bytes32 offerHash,
        bool floorTerm,
        ILSSVMPair lssvmPair,
        uint256 nftId
    ) external payable;

    /// @notice Allows purchaseWithFinancingSudoswap to interact directly with the lending contract
    /// @param offer The details of the loan offer
    /// @param borrower The prospecive borrower on the loan
    /// @param lssvmPair Sudoswap nft-token pair pool.
    /// @param nftId Id of the NFT the borrower intends to purchase.
    function doPurchaseWithFinancingSudoswap(
        Offer memory offer,
        address borrower,
        ILSSVMPair lssvmPair,
        uint256 nftId
    ) external payable;
}
