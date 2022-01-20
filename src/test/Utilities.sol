// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface Hevm {
    // sets the block timestamp to x
    function warp(uint256 x) external;

    // sets the block number to x
    function roll(uint256 x) external;

    // sets the slot loc of contract c to val
    function store(
        address c,
        bytes32 loc,
        bytes32 val
    ) external;

    // reads the slot loc of contract c
    function load(address c, bytes32 loc) external returns (bytes32 val);

    // Signs the digest using the private key sk. Note that signatures produced via hevm.sign will leak the private key.
    function sign(uint sk, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);

    // performs the next smart contract call setting both msg.sender and tx.origin
    function prank(address sender, address origin) external;
}

contract TestUtility {
    Hevm hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function sendViaCall(address payable _to, uint256 amount) public payable {
        // Call returns a boolean value indicating success or failure.
        // This is the current recommended method to use.
        (bool sent, bytes memory data) = _to.call{value: amount}("");
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



contract MockERC721Token is ERC721, ERC721Enumerable, Ownable {
    constructor(string memory name, string memory symbol)
    ERC721(name, symbol)
    {}

    function safeMint(address to, uint256 tokenId) public onlyOwner {
        _safeMint(to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721, ERC721Enumerable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
