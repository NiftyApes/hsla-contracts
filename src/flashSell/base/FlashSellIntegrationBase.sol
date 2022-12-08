// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "../interfaces/IFlashSellReceiver.sol";

/// @notice Base contract to integrate any nft marketplace with NiftyApesFlashSell
/// @title NiftyApes FlashSellIntegrationBase
/// @custom:version 1.0
/// @author zishansami102 (zishansami.eth)
/// @custom:contributor captnseagraves (captnseagraves.eth)
abstract contract FlashSellIntegrationBase is
    OwnableUpgradeable,
    ERC721HolderUpgradeable,
    IFlashSellReceiver
{
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event FlashSellContractAddressUpdated(
        address oldFlashSellContractAddress,
        address newFlashSellContractAddress
    );

    address public flashSellContractAddress;

    /// @notice The initializer for the FlashSellIntegrationBase Contract.
    ///         This contract is intended to be deployed behind a proxy amd thus needs to initialize
    ///         its state outsize of a constructor.
    function initialize() public virtual initializer {
        OwnableUpgradeable.__Ownable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }

    /// @notice Updates the associated flashSell contract address
    function updateFlashSellContractAddress(address newFlashSellContractAddress) external {
        require(address(newFlashSellContractAddress) != address(0), "00035");
        emit FlashSellContractAddressUpdated(flashSellContractAddress, newFlashSellContractAddress);
        flashSellContractAddress = newFlashSellContractAddress;
    }

    /// @inheritdoc IFlashSellReceiver
    function executeOperation(
        address nftContractAddress,
        uint256 nftId,
        address loanAsset,
        uint256 loanAmount,
        address initiator,
        bytes calldata data
    ) external virtual override payable returns (bool) {
        _requireFlashSellContract();

        uint256 assetBalanceBefore = _getAssetBalance(loanAsset);

        _executeTheSale(nftContractAddress, nftId, loanAsset, loanAmount, data);

        uint256 assetBalanceAfter = _getAssetBalance(loanAsset);

        _sendFundsToBothParties(loanAsset, assetBalanceAfter - assetBalanceBefore, loanAmount, initiator);

        return true;
    }

    function _executeTheSale(
        address nftContractAddress,
        uint256 nftId,
        address loanAsset,
        uint256 loanAmount,
        bytes calldata data
    ) internal virtual;

    function _sendFundsToBothParties(
        address loanAsset,
        uint256 assetBalanceDelta,
        uint256 loanAmount,
        address initiator
    ) internal virtual {
        // require assets received are enough to settle the loan
        require(assetBalanceDelta >= loanAmount, "00066");

        if (loanAsset == address(0)) {
            // transfer the asset to FlashSell to allow settling the loan
            payable(flashSellContractAddress).sendValue(loanAmount);
            // transfer the remaining to the initiator
            payable(initiator).sendValue(assetBalanceDelta - loanAmount);
        } else {
            // transfer the asset to FlashSell to allow settling the loan
            IERC20Upgradeable(loanAsset).safeTransfer(flashSellContractAddress, loanAmount);
            // transfer the remaining to the initiator
            IERC20Upgradeable(loanAsset).safeTransfer(initiator, assetBalanceDelta - loanAmount);
        }
    }
    
    function _getAssetBalance(address asset) internal view returns(uint256) {
        if (asset == address(0)) {
            return address(this).balance;
        } else {
            return IERC20Upgradeable(asset).balanceOf(address(this));
        }
    }

    function _requireFlashSellContract() internal view {
        require(msg.sender == flashSellContractAddress, "00031");
    }
}