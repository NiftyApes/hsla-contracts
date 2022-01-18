// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ICToken.sol";

interface ICERC20 is ICToken {
    function mint(uint256) external returns (uint256);

    function borrow(uint256) external returns (uint256);

    function repayBorrowBehalf(address, uint256) external returns (uint256);

    function underlying() external view returns (IERC20);
}
