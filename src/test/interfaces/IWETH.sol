// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

interface IWETH {
    function balanceOf(address) external returns (uint256);

    function deposit() external payable;
}
