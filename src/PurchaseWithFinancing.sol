//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "./Lending.sol";
import "./interfaces/niftyapes/purchaseWithFinancing/IPurchaseWithFinacing.sol";
import "./interfaces/niftyapes/purchaseWithFinancing/ISeaport.sol";
import "forge-std/Test.sol";

contract PurchaseWithFinancing is NiftyApesLending, IPurchaseWithFinancing {
    ISeaport public seaport;

    /// @dev this should be taken from `Lending.sol` but it's marked private and not internal.
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // borrower = msg.sender
    // lender = offer.creator
    function purchaseWithFinancingOpenSea(
        Offer memory offer,
        ISeaport.BasicOrderParameters calldata order
    ) external payable whenNotPaused nonReentrant {
        // Ensure offer isn't an empty offer
        require(offer.asset != address(0), "00004");

        _requireLenderOffer(offer);

        // check msg.sender’s balance

        // require offer.nftContract + offer.nftId == order.offerToken + order.offerIdentifier (NFT)
        _requireMatchingNFTContract(offer.nftContractAddress, order.offerToken);
        _requireMatchingNftId(offer, order.offerIdentifier);

        // require offer.asset == order.considerationToken (ETH)
        _requireMatchingAsset(offer.asset, ETH_ADDRESS);
        _requireSeaportNativeETH(order);

        // require msg.value == order.offerAmount - offer.amount (ETH amount)
        require(msg.value == (order.considerationAmount - offer.amount), "00103"); // "Invalid msg.value"
        // update the lender’s balance in NiftyApes (subtract required amount)
        uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
            offer.asset,
            offer.amount
        );

        // redeemUnderlying asset from the lenders balance (convert required amount)
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(ETH_ADDRESS);
        ILiquidity(liquidityContractAddress).withdrawCBalance(offer.creator, cAsset, cTokensBurned);

        // execute “fulfillBasicOrder” function
        bool success = seaport.fulfillBasicOrder{ value: offer.amount }(order);
        require(success, "00101"); // "Unsuccessful Seaport transaction"

        // update loanAuction struct (this should be similar functionality to `_createLoan()`);
        LoanAuction storage loanAuction = _getLoanAuctionInternal(
            offer.nftContractAddress,
            offer.nftId
        );
        _createSeaportLoan(loanAuction, offer);

        emit LoanExecutedForOpenSea(offer.nftContractAddress, offer.nftId, offer);
    }

    /// @dev based off of to _createLoan in Lender.sol
    function _createSeaportLoan(LoanAuction storage loanAuction, Offer memory offer) internal {
        loanAuction.nftOwner = msg.sender;
        loanAuction.lender = offer.creator;
        loanAuction.asset = offer.asset;
        loanAuction.amount = offer.amount;
        loanAuction.loanEndTimestamp = _currentTimestamp32() + offer.duration;
        loanAuction.loanBeginTimestamp = _currentTimestamp32();
        loanAuction.lastUpdatedTimestamp = _currentTimestamp32();
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;
        loanAuction.lenderRefi = false;
        loanAuction.accumulatedLenderInterest = 0;
        loanAuction.accumulatedProtocolInterest = 0;
        loanAuction.interestRatePerSecond = offer.interestRatePerSecond;
        loanAuction.protocolInterestRatePerSecond = calculateInterestPerSecond(
            offer.amount,
            protocolInterestBps,
            offer.duration
        );
        console.log(
            "createSeaportLoan loanAuction.protocolInterestRatePerSecond",
            loanAuction.protocolInterestRatePerSecond
        );
        loanAuction.slashableLenderInterest = 0;
    }

    function _requireMatchingNFTContract(address nftAddress1, address nftAddress2) internal view {
        require(nftAddress1 == nftAddress2, "00101"); // "NFT Contracts do not match"
    }

    function _requireSeaportNativeETH(ISeaport.BasicOrderParameters calldata order) internal view {
        require(order.considerationToken == address(0), "00102"); // "Must be native ETH"
    }
}
