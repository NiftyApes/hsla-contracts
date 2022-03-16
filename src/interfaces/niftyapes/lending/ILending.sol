//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./ILendingEvents.sol";
import "./ILendingStructs.sol";

/// @title The lending interface for Nifty Apes
///        This interface is intended to be used for interacting with loans on the protocol.
interface ILending is ILendingEvents, ILendingStructs {
    /// @notice Returns the fee that computes protocol interest
    ///         Fees are denomiated in basis points, parts of 10_000
    function loanDrawFeeProtocolBps() external view returns (uint16);

    /// @notice Returns the fee for refinancing a loan that the new lender has to pay
    ///         Fees are denomiated in basis points, parts of 10_000
    function refinancePremiumLenderBps() external view returns (uint16);

    /// @notice Returns the fee for refinancing a loan that is paid to the protocol
    ///         Fees are denomiated in basis points, parts of 10_000
    function refinancePremiumProtocolBps() external view returns (uint16);

    // TODO(dankurka): move
    /// @notice Returns the owner of a given nft if there is a current loan on the NFT, otherwise zero.
    /// @param nftContractAddress The address of the given nft contract
    /// @param nftId The id of the given nft
    function ownerOf(address nftContractAddress, uint256 nftId) external view returns (address);

    /**
     * @notice Retrieve data about a given loan auction
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of a specified NFT
     */
    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory auction);

    /**
     * @notice Generate a hash of an offer and sign with the EIP712 standard
     * @param offer The details of a loan auction offer
     */
    function getEIP712EncodedOffer(Offer memory offer) external view returns (bytes32 signedOffer);

    /**
     * @notice Check whether a signature-based offer has been cancelledOrFinalized
     * @param signature A signed offerHash
     */
    function getOfferSignatureStatus(bytes calldata signature) external view returns (bool status);

    /**
     * @notice Cancel a signature based offer on chain
     * @dev This function is the only way to ensure an offer can't be used on chain
     */
    function withdrawOfferSignature(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bytes calldata signature
    ) external;

    /**
     * @notice Retrieve an offer from the on-chain floor or individual NFT offer books by offerHash identifier
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer
     * @param floorTerm Indicates whether this is a floor or individual NFT offer. true = floor offer. false = individual NFT offer
     */
    function getOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external view returns (Offer memory offer);

    /**
     * @param offer The details of the loan auction individual NFT offer
     */
    function createOffer(Offer calldata offer) external;

    /**
     * @notice Remove an offer in the on-chain floor offer book
     * @param nftContractAddress The address of the NFT collection
     * @param offerHash The hash of all parameters in an offer
     */
    function removeOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external;

    /**
     * @notice Allows a borrower to submit an offer from the on-chain NFT offer book and execute a loan using their NFT as collateral
     * @param nftContractAddress The address of the NFT collection
     * @param floorTerm Whether or not this is a floor term
     * @param nftId The id of the specified NFT (ignored for floor term)
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
    function executeLoanByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external payable;

    /**
     * @notice Allows a borrower to submit a signed offer from a lender and execute a loan using their NFT as collateral
     * @param offer The details of the loan auction offer
     * @param signature A signed offerHash
     * @param nftId The id of a specified NFT
     */
    function executeLoanByBorrowerSignature(
        Offer calldata offer,
        bytes memory signature,
        uint256 nftId
    ) external payable;

    /**
     * @notice Allows a lender to submit an offer from the borrower in the on-chain individual NFT offer book and execute a loan using the borrower's NFT as collateral
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
    function executeLoanByLender(
        address nftContractAddress,
        bool floorTerm,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    /**
     * @notice Allows a lender to submit a signed offer from a borrower and execute a loan using the borrower's NFT as collateral
     * @param offer The details of the loan auction offer
     * @param signature A signed offerHash
     */
    function executeLoanByLenderSignature(Offer calldata offer, bytes calldata signature)
        external
        payable;

    /**
     * @notice Allows a borrower to submit an offer from the on-chain offer book and refinance a loan with near arbitrary terms
     * @dev The offer amount must be greater than the current loan amount plus interest owed to the lender
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param offerHash The hash of all parameters in an offer. This is used as the uniquge identifer of an offer.
     */
    function refinanceByBorrower(
        address nftContractAddress,
        bool floorTerm,
        uint256 nftId,
        bytes32 offerHash
    ) external payable;

    /**
     * @notice Allows a borrower to submit a signed offer from a lender and refinance a loan with near arbitrary terms
     * @dev The offer amount must be greater than the current loan amount plus interest owed to the lender
     * @param offer The details of the loan auction offer
     * @param signature A signed offerHash
     * @param nftId The id of a specified NFT
     */
    function refinanceByBorrowerSignature(
        Offer calldata offer,
        bytes memory signature,
        uint256 nftId
    ) external payable;

    /**
     * @notice Allows a lender to offer better terms than the current loan, refinance, and take over a loan
     * @dev The offer amount, interest rate, and duration must be at parity with the current loan, plus "1". Meaning at least one term must be better than the current loan.
     * @dev new lender balance must be sufficient to pay fullRefinance amount
     * @dev current lender balance must be sufficient to fund new offer amount
     * @param offer The details of the loan auction offer
     */
    function refinanceByLender(Offer calldata offer) external payable;

    /**
     * @notice If a loan has been refinanced with a longer duration this function allows a borrower to draw down additional time for their loan.
     * @dev Drawing down time increases the maximum loan pay back amount and so is not automatically imposed on a refinance by lender, hence this function.
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param drawTime The amount of time to draw and add to the loan duration
     */
    function drawLoanTime(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawTime
    ) external;

    /**
     * @notice If a loan has been refinanced with a higher amount this function allows a borrower to draw down additional value for their loan.
     * @dev Drawing down value increases the maximum loan pay back amount and so is not automatically imposed on a refinance by lender, hence this function.
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param drawAmount The amount of value to draw and add to the loan amountDrawn
     */
    function drawLoanAmount(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawAmount
    ) external;

    /**
     * @notice Enables a borrower to repay the remaining value of their loan plus interest and protocol fee, and regain full ownership of their NFT
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     */
    function repayLoan(address nftContractAddress, uint256 nftId) external payable;

    /**
     * @notice Allows borrowers to make a partial payment toward the principle of their loan
     * @dev This function does not charge any interest or fees. It does change the calculation for future interest and fees accrual, so we track historicLenderInterest and historicProtocolInterest
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     * @param amount The amount of value to pay down on the principle of the loan
     */
    function partialRepayLoan(
        address nftContractAddress,
        uint256 nftId,
        uint256 amount
    ) external payable;

    /**
     * @notice Allows anyone to seize an asset of a past due loan on behalf on the lender
     * @dev This functions can be called by anyone the second the duration + loanExecutedTime is past and the loan is not paid back in full
     * @param nftContractAddress The address of the NFT collection
     * @param nftId The id of the specified NFT
     */
    function seizeAsset(address nftContractAddress, uint256 nftId) external;

    function calculateInterestAccrued(address nftContractAddress, uint256 nftId)
        external
        view
        returns (uint256, uint256);
}
