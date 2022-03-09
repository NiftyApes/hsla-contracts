//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./ILendingAuctionStructs.sol";

interface ILendingAuctionEvents {
    event NewOffer(ILendingAuctionStructs.Offer offer, bytes32 offerHash);

    event OfferRemoved(ILendingAuctionStructs.Offer offer, bytes32 offerHash);

    event LoanExecuted(
        address lender,
        address nftOwner,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        ILendingAuctionStructs.Offer offer
    );

    event Refinance(
        address lender,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        ILendingAuctionStructs.Offer offer
    );

    // cancellation sig event
    event SigOfferCancelled(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        bytes signature
    );

    // finalize sig event
    event SigOfferFinalized(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        bytes signature
    );

    event TimeDrawn(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        uint256 drawTime,
        uint256 totalDrawn
    );

    event AmountDrawn(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        uint256 drawAmount,
        uint256 totalDrawn
    );

    event LoanRepaid(address indexed nftContractAddress, uint256 indexed nftId);

    event PartialRepayment(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address asset,
        uint256 amount
    );

    event AssetSeized(address indexed nftContractAddress, uint256 indexed nftId);
}
