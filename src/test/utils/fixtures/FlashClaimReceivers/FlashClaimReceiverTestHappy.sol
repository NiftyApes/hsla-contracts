// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { IFlashClaimReceiver } from "../../../../flashClaim/interfaces/IFlashClaimReceiver.sol";

import "forge-std/Test.sol";

contract FlashClaimReceiverBaseHappy is IFlashClaimReceiver, ERC721HolderUpgradeable {
    address public flashClaim;

    function updateFlashClaimContractAddress(address newFlashClaimContractAddress) external {
        flashClaim = newFlashClaimContractAddress;
    }

    function executeOperation(
        address initiator,
        address nftContractAddress,
        uint256 nftId,
        bytes calldata data
    ) external returns (bool) {
        initiator;
        data;

        address nftOwner = IERC721Upgradeable(nftContractAddress).ownerOf(nftId);

        console.log("I'm useful! I own this NFT.", nftOwner);
        console.log("This proves I own this NFT.", address(this));

        IERC721Upgradeable(nftContractAddress).approve(address(flashClaim), nftId);

        return true;
    }
}
