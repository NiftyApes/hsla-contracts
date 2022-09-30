// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { IFlashClaimReceiver } from "../interfaces/IFlashClaimReceiver.sol";

/// @title FlashClaimReceiverBase
/// @author Aave
/// @notice Base contract to develop a flashloan-receiver contract.
abstract contract FlashClaimReceiverBase is IFlashClaimReceiver {
    // do logic here
}
