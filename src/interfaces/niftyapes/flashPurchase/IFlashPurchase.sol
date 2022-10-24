//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IFlashPurchaseAdmin.sol";
import "./IFlashPurchaseEvents.sol";
import "../offers/IOffersStructs.sol";
import "../lending/ILendingStructs.sol";
import "../../seaport/ISeaport.sol";
import "../../sudoswap/ILSSVMPair.sol";

interface IFlashPurchase is
    IFlashPurchaseAdmin,
    IFlashPurchaseEvents,
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

    /// @notice Allows a user to borrow ETH/Tokens to purchase NFTs with the condition that
    ///         the purchased NFT is approved to be added as collateral.
    /// @param  offerHash Hash of the existing offer in NiftyApes on-chain offerBook.
    /// @param  nftContractAddress Address of the NFT collection to be pruchased
    /// @param  nftId Token id of the NFT user intends to provide as collateral
    /// @param  floorTerm Determines if this is a floor offer or not.
    /// @param  receiver The address of the external contract that will receive the finance and return the nft.
    /// @param  borrower The address that will be able to later repay the borrowed funds and unlock the nft.
    /// @param  data Arbitrary data structure, intended to contain user-defined parameters, to be passed on to the receiver.
    function borrow(
        bytes32 offerHash,
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm,
        address receiver,
        address borrower,
        bytes calldata data
    ) external;

    /// @notice Allows a user to borrow ETH/Tokens to purchase NFTs with the condition that
    ///         the purchased NFT is approved to be added as collateral.
    /// @param  offer The details of the loan auction offer
    /// @param  signature The signature for the offer
    /// @param  nftId Token id of the NFT user intends to provide as collateral
    /// @param  receiver The address of the external contract that will receive the finance and return the nft.
    /// @param  borrower The address that will be able to later repay the borrowed funds and unlock the nft.
    /// @param  data Arbitrary data structure, intended to contain user-defined parameters, to be passed on to the receiver.
    function borrowSignature(
        Offer memory offer,
        bytes memory signature,
        uint256 nftId,
        address receiver,
        address borrower,
        bytes calldata data
    ) external;
}
