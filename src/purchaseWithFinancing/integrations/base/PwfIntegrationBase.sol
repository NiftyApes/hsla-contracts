// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "../../../interfaces/niftyapes/offers/IOffers.sol";
import "../IFinanceReceiver.sol";

/// @title PwfIntegrationBase
/// @author zishansami102
/// @notice Base contract to integrate any nft marketplace with PurchaseWithFinancing
abstract contract PwfIntegrationBase is
    IFinanceReceiver,
    IOffersStructs 
{
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev Internal address used for for ETH
    address internal constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    function _fetchOffer(
        address offersContract,
        address nftContractAddress,
        bytes32 offerHash,
        bool floorTerm,
        uint256 nftId
    ) internal view returns(Offer memory offer) {
        // fetch offer
        offer = IOffers(offersContract).getOffer(
            nftContractAddress,
            nftId,
            offerHash,
            floorTerm
        );
    }

    function _arrangeAssetFromBorrower(
        address borrower,
        address offerAsset,
        uint256 offerAmount,
        uint256 considerationAmount
    ) internal {
        uint256 considerationDelta = considerationAmount - offerAmount;
        if (offerAsset == ETH_ADDRESS) {
            require(msg.value >= considerationDelta, "00047");
            if (msg.value > considerationDelta) {
                payable(borrower).sendValue(msg.value - considerationDelta);
            }
        } else {
            IERC20Upgradeable asset = IERC20Upgradeable(offerAsset);
            asset.safeTransferFrom(borrower, address(this), considerationDelta);
        }
    }

    function _verifySenderAndInitiator(address initiator, address purchaseWithFinancing) internal view {
        require(msg.sender == purchaseWithFinancing, "0052");
        require(initiator == address(this), "0054");
    }

    function _requireMatchingAsset(address asset1, address asset2) internal pure {
        if (asset2 == address(0)) {
            require(asset1 == ETH_ADDRESS, "00019");
        } else {
            require(asset1 == asset2, "00019");
        }
    }
}