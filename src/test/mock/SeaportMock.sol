// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../interfaces/seaport/ISeaport.sol";
import "./ERC721Mock.sol";
import "forge-std/console.sol";

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

    function fulfillOrder(Order calldata order, bytes32 fulfillerConduitKey)
        external
        payable
        returns (bool fulfilled)
    {
        // require(parameters.considerationToken == address(0), "Must use ETH");
        // require(parameters.considerationIdentifier != 0, "Invalid NFT ID");
        // uint256 testNFTPrice = 100 ether;
        // if (msg.value != testNFTPrice) {
        //     console.log("bad price");
        //     return false;
        // }
        // uint256 testTokenId = 1;
        // if (parameters.considerationIdentifier != testTokenId) {
        //     console.log("bad tokenId");
        //     return false;
        // }
        // console.log("transferring token");
        // mockNft.safeTransferFrom(address(this), msg.sender, testTokenId);
        return true;
    }

    function getCounter(address offerer)
    external
    view
    returns (uint256 counter) {
        return 0;
    }

    function getOrderHash(OrderComponents calldata order)
    external
    view
    returns (bytes32 orderHash) {
        revert();
    }

    /**
     * @dev The full set of order components, with the exception of the counter,
     *      must be supplied when fulfilling more sophisticated orders or groups of
     *      orders. The total number of original consideration items must also be
     *      supplied, as the caller may specify additional consideration items.
     */

    function getOrderStatus(bytes32 orderHash)
    external
    view
    returns (
        bool isValidated,
        bool isCancelled,
        uint256 totalFilled,
        uint256 totalSize
    )
    {
        return (true, true, 0, 0);
    }


}
