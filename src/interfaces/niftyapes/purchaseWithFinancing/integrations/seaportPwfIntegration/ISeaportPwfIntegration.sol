//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "./ISeaportPwfIntegrationAdmin.sol";
import "./ISeaportPwfIntegrationEvents.sol";
import "../../../offers/IOffersStructs.sol";
import "../../../../seaport/ISeaport.sol";

interface ISeaportPwfIntegration is
    ISeaportPwfIntegrationAdmin,
    ISeaportPwfIntegrationEvents,
    IOffersStructs
{
    /// @notice Returns the address for the associated offers contract
    function offersContractAddress() external view returns (address);

    /// @notice Returns the address for the associated offers contract
    function purchaseWithFinancingContractAddress() external view returns (address);

    /// @notice Returns the address for the associated seaport contract
    function seaportContractAddress() external view returns (address);

    /// @notice Allows a user to borrow assets to purchase NFTs on Seaport.
    /// @param offerHash Hash of the existing offer in NiftyApes on-chain offerBook
    /// @param floorTerm Determines if this is a floor offer or not.
    /// @param order Seaport parameters the caller is expected to fill out.
    /// @param fulfillerConduitKey Seaport conduit key of the fulfiller.
    function purchaseWithFinancingSeaport(
        bytes32 offerHash,
        bool floorTerm,
        ISeaport.Order calldata order,
        bytes32 fulfillerConduitKey
    ) external payable;

    /// @notice Allows a user to borrow assets to purchase NFTs on Seaport through signature approved offers.
    /// @param  offer The details of the loan auction offer.
    /// @param  signature The signature for the offer.
    /// @param  order Seaport parameters the caller is expected to fill out.
    /// @param  fulfillerConduitKey Seaport conduit key of the fulfiller.
    function purchaseWithFinancingSeaportSignature(
        Offer memory offer,
        bytes memory signature,
        ISeaport.Order calldata order,
        bytes32 fulfillerConduitKey
    ) external payable;
}
