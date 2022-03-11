pragma solidity ^0.8.11;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ILendingAuction.sol";
import "./interfaces/rarible/IExchangeV2Core.sol";
import "./lib/LibOrder.sol";

contract PurchaseWithFinancing is Ownable {
    using SafeERC20 for IERC20;
    address public lendingAuction;
    address public raribleExchance;

    constructor(address _lendingAuction, address _raribleExchance) {
        lendingAuction = _lendingAuction;
        raribleExchance = _raribleExchance;
    }

    function purchaseWithFinancingRarible(
        ILendingAuction.Offer memory offer,
        LibOrder.Order memory orderLeft,
        bytes memory signatureLeft,
        LibOrder.Order memory orderRight,
        bytes memory signatureRight
    ) external {
        // To simplify smart contract logic, let's make sure left-order is always sell order
        require(orderLeft.taker == address(0), "Make sure left order is sell order of rarible");

        // Validate offer NFT is the same as orderLeft nft
        require(
            orderLeft.makeAsset.assetType.assetClass == LibAsset.ERC721_ASSET_CLASS,
            "Non ERC721 sell order"
        );
        (address token, uint256 tokenId) = abi.decode(
            orderLeft.makeAsset.assetType.data,
            (address, uint256)
        );
        require(token == offer.nftContractAddress, "NFT contract address mismatch");
        require(tokenId == offer.nftId, "NFT tokenID mismatch");

        // Validate take order asset
        require(
            orderLeft.takeAsset.assetType.assetClass == LibAsset.ERC20_ASSET_CLASS,
            "Non ERC20 buy order"
        );
        address takeToken = abi.decode(orderLeft.takeAsset.assetType.data, (address));
        require(takeToken == offer.asset, "ERC20 asset mismatch");
        uint256 userBalance = IERC20(offer.asset).balanceOf(msg.sender);
        require(userBalance + offer.amount >= orderLeft.takeAsset.value, "Not sufficient fund");

        // Transfer ERC20 token
        if (offer.amount < orderLeft.takeAsset.value) {
            IERC20(offer.asset).safeTransferFrom(
                msg.sender,
                address(this),
                orderLeft.takeAsset.value - offer.amount
            );
        }

        ILendingAuction(lendingAuction).executeLoanWithPurchaseFinancing(
            offer,
            offer.creator,
            msg.sender
        );

        IExchangeV2Core(raribleExchance).matchOrders(
            orderLeft,
            signatureLeft,
            orderRight,
            signatureRight
        );

        // Transfer NFT
        IERC721(offer.nftContractAddress).safeTransferFrom(msg.sender, lendingAuction, tokenId);
    }

    function setLendingAuction(address _lendingAuction) external onlyOwner {
        require(lendingAuction != _lendingAuction, "Already set");
        lendingAuction = _lendingAuction;
    }

    function setRaribleExchangeAddress(address _raribleExchance) external onlyOwner {
        require(raribleExchance != _raribleExchance, "Already set");
        raribleExchance = _raribleExchance;
    }
}
