//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IFlashSellAdmin.sol";
import "./IFlashSellEvents.sol";
import "../lending/ILendingStructs.sol";

interface IFlashSell is
    IFlashSellAdmin,
    IFlashSellEvents,
    ILendingStructs
{
    /// @notice Returns the address for the associated lending contract
    function lendingContractAddress() external view returns (address);

    /// @notice Returns the address for the associated liquidity contract
    function liquidityContractAddress() external view returns (address);

    /// @notice Allows a borrower to borrow its locked NFT for sale to external NFT marketplace with the condition that
    ///         the total loan asset amount required to close the loan is sent to the FlashSell contract within the same transaction.
    /// @param  nftContractAddress Address of the NFT collection
    /// @param  nftId Token id of the NFT
    /// @param  receiver The address of the external contract that will receive the NFT and will be called for execution of the sale
    /// @param  data Arbitrary data structure, intended to contain user-defined parameters, to be passed on to the receiver
     function borrowNFTForSale(
        address nftContractAddress,
        uint256 nftId,
        address receiver,
        bytes calldata data
    ) external;

    function initialize() external;
}