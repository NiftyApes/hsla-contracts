//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ISudoswapFlashPurchaseIntegrationAdmin.sol";
import "./ISudoswapFlashPurchaseIntegrationEvents.sol";
import "../../niftyapes/offers/IOffersStructs.sol";
import "../../sudoswap/ILSSVMPair.sol";

interface ISudoswapFlashPurchaseIntegration is
    ISudoswapFlashPurchaseIntegrationAdmin,
    ISudoswapFlashPurchaseIntegrationEvents,
    IOffersStructs
{
    /// @notice Returns the address for the associated offers contract
    function offersContractAddress() external view returns (address);

    /// @notice Returns the address for the associated offers contract
    function flashPurchaseContractAddress() external view returns (address);

    /// @notice Returns the address for the associated sudoswap router
    function sudoswapRouterContractAddress() external view returns (address);

    /// @notice Returns the address for the associated sudoswap factory
    function sudoswapFactoryContractAddress() external view returns (address);

    /// @notice Allows a user to borrow ETH using FlashPurchaseFinance and purchase NFTs through Sudoswap.
    /// @param offerHash Hash of the existing offer in NiftyApes on-chain offerBook.
    /// @param lssvmPair Sudoswap nft-token pair pool.
    /// @param nftIds Ids of the NFT the borrower intends to buy.
    function flashPurchaseSudoswap(
        bytes32 offerHash,
        ILSSVMPair lssvmPair,
        uint256[] memory nftIds
    ) external payable;

    /// @notice Allows a user to borrow assets to purchase NFTs on Sudoswap through signature approved offers.
    /// @param  offer The details of the loan auction offer.
    /// @param  signature The signature for the offer.
    /// @param  lssvmPair Sudoswap nft-token pair pool.
    /// @param nftIds Ids of the NFT the borrower intends to buy.
    function flashPurchaseSudoswapSignature(
        Offer memory offer,
        bytes memory signature,
        ILSSVMPair lssvmPair,
        uint256[] memory nftIds
    ) external payable;
}
