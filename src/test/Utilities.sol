// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "./common/Hevm.sol";

contract TestUtility {
    Hevm public hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function sendViaCall(address payable _to, uint256 amount) public payable {
        // Call returns a boolean value indicating success or failure.
        // This is the current recommended method to use.
        (bool sent, bytes memory data) = _to.call{ value: amount }("");
        require(sent, "Failed to send Ether");
    }
}

interface IWETH {
    function balanceOf(address) external returns (uint256);

    function deposit() external payable;
}

interface IUniswapV2Router {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}
