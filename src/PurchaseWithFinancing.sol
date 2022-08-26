//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "./Lending.sol";
import "./interfaces/niftyapes/purchaseWithFinancing/IPurchaseWithFinacing.sol";
import "./interfaces/niftyapes/purchaseWithFinancing/ISeaport.sol";
import "forge-std/Test.sol";

contract PurchaseWithFinancing is NiftyApesLending, IPurchaseWithFinancing {
    ISeaport public seaport;

    /// @dev this should be taken from `Lending.sol` but it's marked private and not internal.
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    constructor(address _seaportAddress) {
        seaport = ISeaport(_seaportAddress);
    }

    // borrower = msg.sender
    // lender = offer.creator
    function purchaseWithFinancingOpenSea(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm,
        ISeaport.BasicOrderParameters calldata order
    ) external payable whenNotPaused nonReentrant {
        Offer memory offer = IOffers(offersContractAddress).getOffer(
            nftContractAddress,
            nftId,
            offerHash,
            floorTerm
        );
        _requireLenderOffer(offer);
        _requireOfferNotExpired(offer);
        _requireMinDurationForOffer(offer);

        _requireMatchingNFTContract(offer.nftContractAddress, order.offerToken);
        if (!offer.floorTerm) {
            _requireMatchingNftId(offer, order.offerIdentifier);
            IOffers(offersContractAddress).removeOffer(
                offer.nftContractAddress,
                offer.nftId,
                offerHash,
                floorTerm
            );
        }

        // Ensure both assets are native ETH
        _requireMatchingAsset(offer.asset, ETH_ADDRESS);
        _requireSeaportNativeETH(order);

        _requireIsNotSanctioned(offer.creator);
        _requireIsNotSanctioned(msg.sender);

        // Ensure enough ETH has been sent in to purchase with NFT (with the help of lender)
        uint256 purchaseAmount = msg.value + offer.amount;
        require(purchaseAmount == order.considerationAmount, "00103"); // "Not enough ETH to purchase NFT"

        // Lender liquidates the borrowed amount to the Liquidity contract
        uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
            offer.asset,
            offer.amount
        );

        // Do some internal accounting so that Liquidity contract knows lender has less balance
        // Also: why is this not done in `burnCErc20()`?
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(ETH_ADDRESS);
        ILiquidity(liquidityContractAddress).withdrawCBalance(offer.creator, cAsset, cTokensBurned);

        // Transfer liquidated funds from Liquidity contract to this contract
        ILiquidity(liquidityContractAddress).sendValue(offer.asset, offer.amount, address(this));

        // Purchase NFT
        bool success = seaport.fulfillBasicOrder{ value: purchaseAmount }(order);
        require(success, "00101"); // "Unsuccessful Seaport transaction"
        require(
            IERC721Upgradeable(offer.nftContractAddress).ownerOf(nftId) == address(this),
            "00018"
        );

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

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
