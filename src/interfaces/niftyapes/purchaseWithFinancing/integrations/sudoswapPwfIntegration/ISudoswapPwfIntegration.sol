//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "./ISudoswapPwfIntegrationAdmin.sol";
import "./ISudoswapPwfIntegrationEvents.sol";
import "../../../offers/IOffersStructs.sol";
import "../../../../sudoswap/ILSSVMPair.sol";

interface ISudoswapPwfIntegration is
    ISudoswapPwfIntegrationAdmin,
    ISudoswapPwfIntegrationEvents,
    IOffersStructs
{
    /// @notice Returns the address for the associated offers contract
    function offersContractAddress() external view returns (address);

    /// @notice Returns the address for the associated offers contract
    function purchaseWithFinancingContractAddress() external view returns (address);

    /// @notice Returns the address for the associated sudoswap router
    function sudoswapRouterContractAddress() external view returns (address);

    /// @notice Returns the address for the associated sudoswap factory
    function sudoswapFactoryContractAddress() external view returns (address);

    /// @notice Allows a user to borrow ETH using PurchaseWithFinance and purchase NFTs through Sudoswap.
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
}
