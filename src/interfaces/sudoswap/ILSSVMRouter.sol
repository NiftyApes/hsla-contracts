// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import "./ILSSVMPair.sol";

interface ILSSVMRouter {
    struct PairSwapSpecific {
        ILSSVMPair pair;
        uint256[] nftIds;
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