//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";

/// @title Moves openzepplins ECDSA implementation into a seperate library to save
///        code size in the main contract.
library ECDSABridge {
    function recover(bytes32 hash, bytes memory signature) external pure returns (address) {
        return ECDSAUpgradeable.recover(hash, signature);
    }
}
