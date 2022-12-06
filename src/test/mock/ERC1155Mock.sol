// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";

contract ERC1155Mock is ERC1155SupplyUpgradeable {
    function initialize() public initializer {
        ERC1155SupplyUpgradeable.__ERC1155Supply_init();
    }

    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount, bytes(""));
    }
}
