// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    bool public transferFromFail;
    bool public transferFail;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        if (transferFromFail) {
            return false;
        }

        return ERC20.transferFrom(from, to, amount);
    }

    function setTransferFromFail(bool fail) external {
        transferFromFail = fail;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (transferFail) {
            return false;
        }

        return ERC20.transfer(to, amount);
    }

    function setTransferFail(bool fail) external {
        transferFail = fail;
    }
}
