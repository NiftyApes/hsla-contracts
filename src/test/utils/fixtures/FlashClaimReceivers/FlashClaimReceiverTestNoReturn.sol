// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { IFlashClaimReceiver } from "../../../../flashClaim/interfaces/IFlashClaimReceiver.sol";

import "forge-std/Test.sol";

/// @title FlashClaimReceiverBase
/// @author captnseagaves
/// @notice Base contract to develop a FlashClaimReceiver contract.

contract FlashClaimReceiverBaseNoReturn is IFlashClaimReceiver, ERC721HolderUpgradeable {
    function executeOperation(
        address nftContractAddress,
        uint256 nftId,
        address niftyApesFlashClaimContractAddress
    ) external pure returns (bool) {
        nftContractAddress;
        nftId;
        niftyApesFlashClaimContractAddress;
        return true;
    }
}
