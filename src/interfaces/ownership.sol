//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/// @title Interface to call transferOwnership on deployed proxy
interface IOwnership {
    /// See Open Zeppelin Ownership documentation
    function transferOwnership(address newOwner) external;
}
