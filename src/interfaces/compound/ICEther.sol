// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ICToken.sol";

interface ICEther is ICToken {
    function mint() external payable;

    function repayBorrow() external payable;

    function repayBorrowBehalf(address borrower) external payable;
}
