//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "../../interfaces/flashSellIntegrations/seaport/ISeaportFlashSellIntegration.sol";
import "../base/FlashSellIntegrationBase.sol";

/// @notice Integration of Seaport to FlashSell to allow sale of NFTs through offers present in Seaport
/// @title SeaportFlashSellIntegration
/// @custom:version 1.0
/// @author zishansami102 (zishansami.eth)
contract SeaportFlashSellIntegration is
    PausableUpgradeable,
    ISeaportFlashSellIntegration,
    FlashSellIntegrationBase
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

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
    function initialize() public override initializer {
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
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

    // @inheritdoc FlashSellIntegrationBase
    function _executeTheSale(
        address nftContractAddress,
        uint256 nftId,
        address loanAsset,
        uint256 loanAmount,
        bytes calldata data
    ) internal override {
        // approve the NFT for Seaport conduit
        IERC721Upgradeable(nftContractAddress).approve(seaportContractAddress, nftId);

        // decode data
        (ISeaport.Order memory order, bytes32 fulfillerConduitKey) = abi.decode(data, (ISeaport.Order, bytes32));
        _requireValidOrderAssets(order, nftContractAddress, nftId, loanAsset);

        IERC20Upgradeable asset;
        if (loanAsset != address(0)) {
            asset = IERC20Upgradeable(loanAsset);
        } else {
            asset = IERC20Upgradeable(wethContractAddress);
        }
        uint256 allowance = asset.allowance(address(this), seaportContractAddress);
        if (allowance > 0) {
            asset.safeDecreaseAllowance(seaportContractAddress, allowance);
        }
        asset.safeIncreaseAllowance(seaportContractAddress, order.parameters.consideration[1].endAmount);

        require(
            ISeaport(seaportContractAddress).fulfillOrder(order, fulfillerConduitKey),
            "00048"
        );
        if (loanAsset == address(0)) {
            // convert weth to eth
            (bool success,) = wethContractAddress.call(abi.encodeWithSignature("withdraw(uint256)", order.parameters.offer[0].endAmount - order.parameters.consideration[1].endAmount));
            require(success, "00068");
        }
    }

    function _requireValidOrderAssets(
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

    /// @notice This contract needs to accept ETH from Seaport
    receive() external payable {}
}
