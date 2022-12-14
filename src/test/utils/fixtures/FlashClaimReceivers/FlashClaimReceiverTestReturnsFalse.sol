// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { IFlashClaimReceiver } from "../../../../flashClaim/interfaces/IFlashClaimReceiver.sol";

import "forge-std/Test.sol";

contract FlashClaimReceiverBaseReturnsFalse is IFlashClaimReceiver, ERC721HolderUpgradeable {
    function executeOperation(
        address initiator,
        address nftContractAddress,
        uint256 nftId,
        bytes calldata data
    ) external pure returns (bool) {
        initiator;
        nftContractAddress;
        nftId;
        data;
        return false;
    }
}
