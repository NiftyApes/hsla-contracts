// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title IFlashClaimReceiver
/// @author captnseagraves
/// @notice Defines the basic interface of a flashClaimReceiver contract.
/// @dev Implement this interface to develop a flashClaim-compatible flashClaimReceiver contract

interface IFlashClaimReceiver {
    /// @notice Executes an operation after receiving the flash claimed nft
    /// @dev Ensure that the contract approves the return of the nft to the NiftyApes flashClaim contract
    ///      before the end of the transaction
    /// @param nftContractAddress The address of the nft collection
    /// @param nftId The id of the specified nft
    /// @return True if the execution of the operation succeeds, false otherwise
    function executeOperation(address nftContractAddress, uint256 nftId) external returns (bool);
}
