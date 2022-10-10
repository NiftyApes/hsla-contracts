// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../purchaseWithFinancing/interfaces/IPurchaseWithFinancingReceiver.sol";

contract FinanceReceiverMock is IPurchaseWithFinancingReceiver, ERC721HolderUpgradeable {
    function executeOperation(
        address nftContractAddress,
        uint256 nftId,
        address initiator,
        bytes calldata data
    ) external payable returns (bool) {
        IERC721Upgradeable(nftContractAddress).approve(msg.sender, nftId);
        return true;
    }

    receive() external payable {}
}
