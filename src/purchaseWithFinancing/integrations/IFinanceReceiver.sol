// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title IFinanceReceiver
/// @author zishansami102
/// @notice Defines the basic interface of a finance receiver contract using `PurchaseWithFinancing.borrow()`
/// @dev Implement this interface to integrate PurchaseWithFinancing to any nft marketplace

interface IFinanceReceiver {
    /// @notice Executes an operation after receiving the lending amount from an existing offer on NiftyApes
    /// @dev Ensure that the contract approves the return of the purchased nft to the PurchaseWithFinancing contract
    ///      before the end of the transaction
    /// @param nftContractAddress The address of the nft collection
    /// @param nftId The id of the specified nft
    /// @param initiator The address which initiated the borrow call on PurchaseWithFinancing contract
    /// @param data generic data input to be used in purchase of the NFT
    /// @return True if the execution of the operation succeeds, false otherwise
    function executeOperation(
        address nftContractAddress,
        uint256 nftId,
        address initiator,
        bytes calldata data
    ) external payable returns (bool);
}