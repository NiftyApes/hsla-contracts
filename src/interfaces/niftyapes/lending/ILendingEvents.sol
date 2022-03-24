//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lending/ILendingStructs.sol";

interface ILendingEvents {
    event NewOffer(
        address indexed creator,
        address asset,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        ILendingStructs.Offer offer,
        bytes32 offerHash
    );

    event OfferRemoved(
        address indexed creator,
        address indexed asset,
        address indexed nftContractAddress,
        ILendingStructs.Offer offer,
        bytes32 offerHash
    );

    event LoanExecuted(
        address indexed lender,
        address borrower,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        ILendingStructs.Offer offer
    );

    event Refinance(
        address lender,
        address indexed nftContractAddress,
        uint256 indexed nftId,
        ILendingStructs.Offer offer
    );

    event OfferSignatureUsed(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        ILendingStructs.Offer offer,
        bytes signature
    );

    event AmountDrawn(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        uint256 drawAmount,
        uint256 totalDrawn
    );

    event LoanRepaid(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address indexed borrower,
        address asset,
        uint256 totalPayment
    );

    event PartialRepayment(
        address indexed nftContractAddress,
        uint256 indexed nftId,
        address asset,
        uint256 amount
    );

    event AssetSeized(
        address indexed lender,
        address borrower,
        address indexed nftContractAddress,
        uint256 indexed nftId
    );
}
