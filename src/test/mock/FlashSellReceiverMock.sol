// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import { IFlashSellReceiver } from "../../flashSell/interfaces/IFlashSellReceiver.sol";

import "forge-std/Test.sol";

contract FlashSellReceiverMock is IFlashSellReceiver, ERC721HolderUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    bool public happyState;

    function updateHappyState(bool newState) external {
        happyState = newState;
    }

    function executeOperation(
        address nftContractAddress,
        uint256 nftId,
        address loanAsset,
        uint256 loanAmount,
        address initiator,
        bytes calldata data
    ) external payable returns (bool) {
        nftContractAddress;
        nftId;
        initiator;
        data;
        if (!happyState) {
            loanAmount = loanAmount - 1;
        }
        if (loanAsset != address(0)) {
            IERC20Upgradeable(loanAsset).safeTransfer(msg.sender, loanAmount);
        } else {
            payable(msg.sender).sendValue(loanAmount);
        }
        return true;
    }

    receive() external payable {}
}