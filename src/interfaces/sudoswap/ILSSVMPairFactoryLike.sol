// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

interface ILSSVMPairFactoryLike {
    enum PairVariant {
        ENUMERABLE_ETH,
        MISSING_ENUMERABLE_ETH,
        ENUMERABLE_ERC20,
        MISSING_ENUMERABLE_ERC20
    }

    function isPair(address potentialPair, PairVariant variant)
        external
        view
        returns (bool);
}