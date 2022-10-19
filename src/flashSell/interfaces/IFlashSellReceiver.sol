// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title IFlashSellReceiver
/// @author zishansami102 (zishansami.eth)
/// @notice Defines the basic interface of a FlashSell Receiver contract using `FlashSell.borrow()`
/// @dev Implement this interface to integrate FlashSell to any nft marketplace

interface IFlashSellReceiver {
    /// @notice Executes sale operation after receiving the NFT from the NiftyApesFlashSell contract.
    /// @dev Ensure that the contract sends appropriate funds for closing the loan to NiftyApesFlashSell contract
    ///      before the end of this function call.
    /// @param nftContractAddress The address of the nft collection
    /// @param nftId The id of the specified nft
    /// @param loanAsset The address of the asset token required to close the loan
    /// @param amount The asset amount required to close the loan to be sent to NiftyApesFlashSell contract
    /// @param initiator The address which initiated this call to FlashSell contract
    /// @param data generic data input to be used for the sale of the NFT
    /// @return True if the execution of the operation succeeds, false otherwise
    function executeOperation(
        address nftContractAddress,
        uint256 nftId,
        address loanAsset,
        uint256 amount,
        address initiator,
        bytes calldata data
    ) external payable returns (bool);
}