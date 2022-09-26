// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../interfaces/sudoswap/ILSSVMRouter.sol";

contract LSSVMRouterMock is ILSSVMRouter {

    function swapETHForSpecificNFTs(
        PairSwapSpecific[] calldata swapList,
        address payable ethRecipient,
        address nftRecipient,
        uint256 deadline
    ) external payable override returns (uint256 remainingValue) {
        return 0;
    }

    function swapERC20ForSpecificNFTs(
        PairSwapSpecific[] calldata swapList,
        uint256 inputAmount,
        address nftRecipient,
        uint256 deadline
    ) external override returns (uint256 remainingValue) {
        return 0;
    }
}
