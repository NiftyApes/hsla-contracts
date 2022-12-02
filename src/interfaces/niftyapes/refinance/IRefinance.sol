//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IRefinanceAdmin.sol";
import "./IRefinanceEvents.sol";
import "../offers/IOffersStructs.sol";

/// @title NiftyApes interface for refinancing loans.
interface IRefinance is IRefinanceAdmin, IRefinanceEvents, IOffersStructs {

    /// @notice Returns the address for the associated lending contract
    function lendingContractAddress() external view returns (address);

    /// @notice Returns the address for the associated offers contract
    function offersContractAddress() external view returns (address);

    /// @notice Returns the address for the associated liquidity contract
    function liquidityContractAddress() external view returns (address);

    /// @notice Returns the address for the associated signature lending contract
    function sigLendingContractAddress() external view returns (address);

    /// @notice Refinance a loan against the on chain offer book as the borrower.
    ///         The new offer has to cover the principle remaining and all lender interest owed on the loan
    ///         Borrowers can refinance at any time even after loan default as long as their NFT collateral has not been seized
    /// @param nftContractAddress The address of the NFT collection
    /// @param nftId The id of the specified NFT
    /// @param floorTerm Indicates whether this is a floor or individual NFT offer.
    /// @param offerHash The hash of all parameters in an offer. This is used as the unique identifier of an offer.
    function refinanceByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm,
        bytes32 offerHash,
        uint32 expectedLastUpdatedTimestamp
    ) external;

    /// @notice Refinance a loan against a new offer.
    ///         The new offer must improve terms for the borrower
    ///         Lender must improve terms by a cumulative 25 bps or pay a 25 bps premium
    ///         For example, if termGriefingPremiumBps is 25 then the cumulative improvement of amount, interestRatePerSecond, and duration must be more than 25 bps
    ///         If the amount is 8 bps better, interestRatePerSecond is 7 bps better, and duration is 10 bps better, then no premium is paid
    ///         If any one of those terms is worse then a full premium is paid
    ///         The Lender must allow 25 bps on interest to accrue or pay a gas griefing premium to the current lender
    ///         This premium is equal to gasGriefingPremiumBps - interestEarned
    /// @param offer The details of the loan auction offer
    /// @param expectedLastUpdatedTimestamp The timestamp of the expected terms. This allows lenders to avoid being frontrun and forced to pay a gasGriefingPremium.
    ///        Lenders can provide a 0 value if they are willing to pay the gasGriefingPremium in a high volume loanAuction
    function refinanceByLender(Offer calldata offer, uint32 expectedLastUpdatedTimestamp) external;

    
    /// @notice Function only callable by the NiftyApesSigLending contract
    ///         Allows SigLending contract to refinance a loan directly
    /// @param offer The details of the loan auction offer
    /// @param nftId The id of the specified NFT
    /// @param nftOwner owner of the nft in the lending.sol lendingAuction
    function doRefinanceByBorrower(
        Offer memory offer,
        uint256 nftId,
        address nftOwner,
        uint32 expectedLastUpdatedTimestamp
    ) external;
}
