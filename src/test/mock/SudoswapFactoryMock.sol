// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../interfaces/sudoswap/ILSSVMPairFactoryLike.sol";
// import "./ERC721Mock.sol";
import "forge-std/console.sol";

contract LSSVMPairFactoryMock is ILSSVMPairFactoryLike {

    function isPair(address potentialPair, PairVariant variant) external view override returns (bool) {
        // TODO: Write function logic based on local unit tests
        return true;
    }

    function createPairERC20(CreateERC20PairParams calldata params) external override returns (ILSSVMPair pair) {
        // TODO: Write function logic based on local unit tests
        pair = ILSSVMPair(address(0));
    }
}
