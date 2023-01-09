//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ISellOnSeaportAdmin.sol";
import "./ISellOnSeaportEvents.sol";
import "./ISellOnSeaportStructs.sol";
import "../lending/ILendingStructs.sol";
import "../../seaport/ISeaport.sol";


interface ISellOnSeaport is
    ISellOnSeaportAdmin,
    ISellOnSeaportEvents,
    ISellOnSeaportStructs,
    ILendingStructs
{
    /// @notice Returns the address for the associated liquidity contract
    function liquidityContractAddress() external view returns (address);

    /// @notice Returns the address for the associated lending contract
    function lendingContractAddress() external view returns (address);

    /// @notice Returns the address for the associated seaport contract
    function seaportContractAddress() external view returns (address);

    /// @notice Returns the address for the seaportZone
    function seaportZone() external view returns (address);

    /// @notice Returns the address for the seaportFeeRecepient
    function seaportFeeRecepient() external view returns (address);

    /// @notice Returns the seaportZoneHash
    function seaportZoneHash() external view returns (bytes32);

    /// @notice Returns the seaportConduitKey
    function seaportConduitKey() external view returns (bytes32);

    /// @notice Returns the seaportConduit
    function seaportConduit() external view returns (address);

    /// @notice Allows a borrower to list their locked NFTs on Seaport
    /// @param  nftContractAddress Address of the NFT collection to be pruchased
    /// @param  nftId Token id of the NFT user intends to provide as collateral
    /// @param  listingPrice Token id of the NFT user intends to provide as collateral
    /// @param  listingStartTime id of the NFT user intends to provide as collateral
    /// @param  listingEndTime Token id of the NFT user intends to provide as collateral
    /// @param  salt a random salt
    /// @return orderHash
    function listNftForSale(
        address nftContractAddress,
        uint256 nftId,
        uint256 listingPrice,
        uint256 listingStartTime,
        uint256 listingEndTime,
        uint256 salt
    ) external returns (bytes32);

    /// @notice Allows a borrower to validate the sale of their listed NFT
    /// @param  nftContractAddress Address of the NFT collection to be pruchased
    /// @param  nftId Token id of the NFT user intends to provide as collateral
    /// @param  orderHash hash of the listed seaport order
    function validateSaleAndWithdraw(
        address nftContractAddress,
        uint256 nftId,
        bytes32 orderHash
    ) external;

    /// @notice Allows a borrower to cancel their NFT listing on Seaport
    /// @param  orderComponents Seaport orderComponent
    function cancelNftListing(ISeaport.OrderComponents memory orderComponents) external;

    function initialize() external;
}
