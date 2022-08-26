// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../interfaces/niftyapes/purchaseWithFinancing/ISeaport.sol";
import "./ERC721Mock.sol";

contract SeaportMock is ISeaport {
    ERC721Mock public mockNft;

    constructor() {
        mockNft = new ERC721Mock();
        mockNft.initialize("BoredApe", "BAYC");
        mockNft.safeMint(address(this), 1);
    }

    function approve(address purchaseWithFinancingContract) external {
        mockNft.approve(purchaseWithFinancingContract, 1);
    }

    function fulfillBasicOrder(BasicOrderParameters calldata parameters)
        external
        payable
        returns (bool fulfilled)
    {
        require(parameters.considerationToken != address(0), "Invalid NFT Address");
        require(parameters.considerationIdentifier != 0, "Invalid NFT ID");

        uint256 testNFTPrice = 100 ether;
        if (msg.value != testNFTPrice) {
            return false;
        }

        uint256 testTokenId = 999;
        if (parameters.considerationIdentifier != testTokenId) {
            return false;
        }

        mockNft.safeTransferFrom(address(this), msg.sender, testTokenId);
        return true;
    }
}
