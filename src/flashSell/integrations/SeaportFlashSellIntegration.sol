//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "../../interfaces/flashSellIntegrations/seaport/ISeaportFlashSellIntegration.sol";
import "../../interfaces/niftyapes/lending/ILending.sol";
import "../../interfaces/niftyapes/liquidity/ILiquidity.sol";
import "../../interfaces/sanctions/SanctionsList.sol";
import "../interfaces/IFlashSellReceiver.sol";

/// @notice Integration of Seaport to FlashSell to allow sale of NFTs through offers present in Seaport
/// @title SeaportFlashSellIntegration
/// @custom:version 1.0
/// @author zishansami102 (zishansami.eth)
contract SeaportFlashSellIntegration is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    ISeaportFlashSellIntegration,
    IFlashSellReceiver
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    /// @inheritdoc ISeaportFlashSellIntegration
    address public flashSellContractAddress;

    /// @inheritdoc ISeaportFlashSellIntegration
    address public wethContractAddress;

    /// @inheritdoc ISeaportFlashSellIntegration
    address public seaportContractAddress;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the SeaportFlashSellIntegration Contract.
    ///         SeaportFlashSellIntegration is intended to be deployed behind a proxy amd thus needs to initialize
    ///         its state outsize of a constructor.
    function initialize() public initializer {
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }

    /// @inheritdoc ISeaportFlashSellIntegrationAdmin
    function updateFlashSellContractAddress(address newFlashSellContractAddress) external onlyOwner {
        require(address(newFlashSellContractAddress) != address(0), "00035");
        emit SeaportFlashSellIntegrationXFlashSellContractAddressUpdated(flashSellContractAddress, newFlashSellContractAddress);
        flashSellContractAddress = newFlashSellContractAddress;
    }

    /// @inheritdoc ISeaportFlashSellIntegrationAdmin
    function updateWethContractAddress(address newWethContractAddress) external onlyOwner {
        require(address(newWethContractAddress) != address(0), "00035");
        emit SeaportFlashSellIntegrationXWethContractAddressUpdated(wethContractAddress, newWethContractAddress);
        wethContractAddress = newWethContractAddress;
    }

    /// @inheritdoc ISeaportFlashSellIntegrationAdmin
    function updateSeaportContractAddress(address newSeaportContractAddress) external onlyOwner {
        require(address(newSeaportContractAddress) != address(0), "00035");
        emit SeaportFlashSellIntegrationXSeaportContractAddressUpdated(seaportContractAddress, newSeaportContractAddress);
        seaportContractAddress = newSeaportContractAddress;
    }

    /// @inheritdoc ISeaportFlashSellIntegrationAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc ISeaportFlashSellIntegrationAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    function executeOperation(
        address nftContractAddress,
        uint256 nftId,
        address loanAsset,
        uint256 loanAmount,
        address initiator,
        bytes calldata data
    ) external payable returns (bool) {
        _requireFlashSellContract();

        // decode data
        (ISeaport.Order memory order, bytes32 fulfillerConduitKey) = abi.decode(data, (ISeaport.Order, bytes32));
        _requireValidOrderAsset(order, nftContractAddress, nftId, loanAsset);

        // approve the NFT for Seaport conduit
        IERC721Upgradeable(nftContractAddress).approve(seaportContractAddress, nftId);

        IERC20Upgradeable asset;
        if (loanAsset != address(0)) {
            asset = IERC20Upgradeable(loanAsset);
        } else {
            asset = IERC20Upgradeable(wethContractAddress);
        }

        uint256 assetBalanceBefore = _getAssetBalance(address(asset));

        uint256 allowance = asset.allowance(address(this), seaportContractAddress);
        if (allowance > 0) {
            asset.safeDecreaseAllowance(seaportContractAddress, allowance);
        }
        asset.safeIncreaseAllowance(seaportContractAddress, order.parameters.consideration[1].endAmount);

        require(
            ISeaport(seaportContractAddress).fulfillOrder(order, fulfillerConduitKey),
            "00048"
        );

        uint256 assetBalanceAfter = _getAssetBalance(address(asset));

        // require assets received are enough to settle the loan
        require(assetBalanceAfter - assetBalanceBefore >= loanAmount, "00066");

        if (loanAsset == address(0)) {
            // convert weth to eth
            (bool success,) = wethContractAddress.call(abi.encodeWithSignature("withdraw(uint256)", assetBalanceAfter - assetBalanceBefore));
            require(success, "00068");
            // transfer the asset to FlashSell to settle the loan
            payable(flashSellContractAddress).sendValue(loanAmount);
            // transfer the remaining to the initiator
            payable(initiator).sendValue(assetBalanceAfter - assetBalanceBefore - loanAmount);
        } else {
            // transfer the asset to FlashSell to settle the loan
            IERC20Upgradeable(loanAsset).safeTransfer(flashSellContractAddress, loanAmount);
            // transfer the remaining to the initiator
            IERC20Upgradeable(loanAsset).safeTransfer(initiator, assetBalanceAfter - assetBalanceBefore - loanAmount);
        }
        return true;
    }

    function _requireValidOrderAsset(
        ISeaport.Order memory order,
        address nftContractAddress,
        uint256 nftId,
        address loanAsset
    ) internal view {
        require(order.parameters.consideration[0].itemType == ISeaport.ItemType.ERC721, "00067");
        require(order.parameters.consideration[0].token == nftContractAddress, "00067");
        require(order.parameters.consideration[0].identifierOrCriteria == nftId, "00067");
        require(order.parameters.offer[0].itemType == ISeaport.ItemType.ERC20, "00067");
        require(order.parameters.consideration[1].itemType == ISeaport.ItemType.ERC20, "00067");
        if (loanAsset == address(0)) {
            require(order.parameters.offer[0].token == wethContractAddress,  "00067");
            require(order.parameters.consideration[1].token == wethContractAddress,  "00067");
        } else {
            require(order.parameters.offer[0].token == loanAsset,  "00067");
            require(order.parameters.consideration[1].token == loanAsset,  "00067");
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

    /// @notice This contract needs to accept ETH from Seaport
    receive() external payable {}
}
