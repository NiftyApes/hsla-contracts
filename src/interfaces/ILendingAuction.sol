//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./ILiquidityProviders.sol";
import "./ILendingAuctionEvents.sol";
import "./ILendingAuctionStructs.sol";

interface ILendingAuction is ILiquidityProviders, ILendingAuctionEvents, ILendingAuctionStructs {
    // Functions
    function loanDrawFeeProtocolBps() external view returns (uint64);

    function refinancePremiumLenderBps() external view returns (uint64);

    function refinancePremiumProtocolBps() external view returns (uint64);

    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory auction);

    function getOfferSignatureStatus(bytes calldata signature) external view returns (bool status);

    function withdrawOfferSignature(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bytes calldata signature
    ) external;

    function getOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external view returns (Offer memory offer);

    function createOffer(Offer calldata offer) external;

    function removeOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external;

    function executeLoanByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external payable;

    function executeLoanByBorrowerSignature(
        Offer calldata offer,
        bytes memory signature,
        uint256 nftId
    ) external payable;

    function executeLoanByLender(
        address nftContractAddress,
        bool floorTerm,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    function executeLoanByLenderSignature(Offer calldata offer, bytes calldata signature)
        external
        payable;

    // function refinanceByBorrower(
    //     address nftContractAddress,
    //     bool floorTerm,
    //     uint256 nftId,
    //     bytes32 offerHash
    // ) external payable;

    // function refinanceByBorrowerSignature(
    //     Offer calldata offer,
    //     bytes memory signature,
    //     uint256 nftId
    // ) external payable;

    // function refinanceByLender(Offer calldata offer) external payable;

    // function drawLoanTime(
    //     address nftContractAddress,
    //     uint256 nftId,
    //     uint256 drawTime
    // ) external;

    // function drawLoanAmount(
    //     address nftContractAddress,
    //     uint256 nftId,
    //     uint256 drawAmount
    // ) external;

    function repayLoan(address nftContractAddress, uint256 nftId) external payable;

    function partialRepayLoan(
        address nftContractAddress,
        uint256 nftId,
        uint256 amount
    ) external payable;

    function seizeAsset(address nftContractAddress, uint256 nftId) external;

    function calculateInterestAccrued(address nftContractAddress, uint256 nftId)
        external
        view
        returns (uint256, uint256);

    function updateLoanDrawProtocolFee(uint64 newLoanDrawProtocolFeeBps) external;

    function updateRefinancePremiumLenderFee(uint64 newPremiumLenderBps) external;

    function updateRefinancePremiumProtocolFee(uint64 newPremiumProtocolBps) external;
}
