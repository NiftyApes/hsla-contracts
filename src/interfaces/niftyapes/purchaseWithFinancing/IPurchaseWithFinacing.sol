//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "../offers/IOffersStructs.sol";
import "./ISeaport.sol";

interface IPurchaseWithFinancing is IOffersStructs {
    /// @notice Allows a user to borrow ETH to purchase NFTs.
    ///         borrower = msg.sender, lender = offer.creator
    /// @param nftId Id of NFT contract borrower would like to purchase
    /// @param offerHash Hash of the existing offer in NiftyApes on-chain offerBook
    /// @param floorTerm Determines if this is a floor offer or not.
    /// @param order Seaport parameters the caller is expected to fill out.
    /// @dev The OrderParametrs are EIP712 compliant with a signature field in the struct.
    ///      This will be enforced and verified by OpenSea, not this function.
    function purchaseWithFinancingSeaport(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm,
        ISeaport.BasicOrderParameters calldata order
    ) external payable;
}
