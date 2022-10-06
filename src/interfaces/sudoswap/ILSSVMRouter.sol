// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import "./ILSSVMPair.sol";

interface ILSSVMRouter {
    struct PairSwapSpecific {
        ILSSVMPair pair;
        uint256[] nftIds;
    }

    enum Error {
        OK, // No error
        INVALID_NUMITEMS, // The numItem value is 0
        SPOT_PRICE_OVERFLOW // The updated spot price doesn't fit into 128 bits
    }

    function swapETHForSpecificNFTs(
        PairSwapSpecific[] calldata swapList,
        address payable ethRecipient,
        address nftRecipient,
        uint256 deadline
    ) external payable returns (uint256 remainingValue);

    function swapERC20ForSpecificNFTs(
        PairSwapSpecific[] calldata swapList,
        uint256 inputAmount,
        address nftRecipient,
        uint256 deadline
    ) external returns (uint256 remainingValue);
}