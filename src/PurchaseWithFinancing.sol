//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "./Lending.sol";
import "./interfaces/niftyapes/purchaseWithFinancing/IPurchaseWithFinacing.sol";
import "./interfaces/niftyapes/purchaseWithFinancing/ISeaport.sol";
import "forge-std/Test.sol";

contract PurchaseWithFinancing is NiftyApesLending, IPurchaseWithFinancing {
    // TODO: Remove this and separate out and leave this as interface.
    // Only here to make things compile
    function fulfillBasicOrder(BasicOrderParameters calldata parameters)
        external
        payable
        returns (bool fulfilled)
    {
        return true;
    }

    function purchaseWithFinancingOpenSea(Offer memory offer, BasicOrderParameters calldata order)
        external
        payable
    {
        // check msg.sender’s balance
        // require offer.nftContract + offer.nftId == order.offerToken + order.offerIdentifier (NFT)
        // require offer.asset == order.considerationToken (ETH)
        // require msg.value == order.offerAmount - offer.amount (ETH amount)
        // update the lender’s balance in NiftyApes (subtract required amount)
        uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
            offer.asset,
            offer.amount
        );
        // redeemUnderlying asset from the lenders balance (convert required amount)
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);
        ILiquidity(liquidityContractAddress).withdrawCBalance(offer.creator, cAsset, cTokensBurned);

        bool success = fulfillBasicOrder{ value: offer.amount }(order);
        require(success, "Unsuccessful Seaport Transaction"); // TODO: Make error code

        // execute “fulfillBasicOrder” function
        // update loanAuction struct (this should be similar functionality to `_createLoan()`);
        emit LoanExecutedForOpenSea(offer.nftContractAddress, offer.nftId, offer);
    }
}
