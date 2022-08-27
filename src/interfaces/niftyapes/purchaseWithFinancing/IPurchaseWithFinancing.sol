//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "./IPurchaseWithFinancingAdmin.sol";
import "./IPurchaseWithFinancingEvents.sol";
import "../offers/IOffersStructs.sol";
import "../lending/ILendingStructs.sol";
import "../../seaport/ISeaport.sol";

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

    /// @notice Allows a user to borrow ETH to purchase NFTs.
    /// @param offerHash Hash of the existing offer in NiftyApes on-chain offerBook
    /// @param floorTerm Determines if this is a floor offer or not.
    /// @param order Seaport parameters the caller is expected to fill out.
    function purchaseWithFinancingSeaport(
        address nftContractAddress,
        bytes32 offerHash,
        bool floorTerm,
        ISeaport.BasicOrderParameters calldata order
    ) external payable;

    /// @notice Allows the PurchaseWithFiancning contract to interact directly with the lending contract
    /// @param offer The details of the loan offer
    /// @param lender The prospective lender on the loan
    /// @param borrower The prospecive borrower on the loan
    /// @param order Seaport parameters the caller is expected to fill out
    /// @param msgValue The value of ETH sent with the original transaction
    function doPurchaseWithFinancingSeaport(
        Offer memory offer,
        address lender,
        address borrower,
        ISeaport.BasicOrderParameters calldata order,
        uint256 msgValue
    ) external payable;
}
