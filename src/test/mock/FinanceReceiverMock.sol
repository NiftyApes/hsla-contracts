// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../purchaseWithFinancing/integrations/IFinanceReceiver.sol";

contract FinanceReceiverMock is IFinanceReceiver, ERC721HolderUpgradeable {
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
