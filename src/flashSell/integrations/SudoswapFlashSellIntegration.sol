//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../interfaces/flashSellIntegrations/sudoswapFlashSellIntegration/ISudoswapFlashSellIntegration.sol";
import "../../interfaces/sudoswap/ILSSVMPairFactoryLike.sol";
import "../../interfaces/sudoswap/ILSSVMPair.sol";
import "../../interfaces/sudoswap/ILSSVMRouter.sol";
import "../interfaces/IFlashSellReceiver.sol";

/// @notice Integration of Sudoswap to FlashSell to allow sale of NFTs to settle the active loans
contract SudoswapFlashSellIntegration is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    PausableUpgradeable,
    ISudoswapFlashSellIntegration,
    IFlashSellReceiver
{
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @inheritdoc ISudoswapFlashSellIntegration
    address public flashSellContractAddress;

    /// @inheritdoc ISudoswapFlashSellIntegration
    address public sudoswapFactoryContractAddress;
    
    /// @inheritdoc ISudoswapFlashSellIntegration
    address public sudoswapRouterContractAddress;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the marketplace integration contract.
    function initialize(
        address newFlashSellContractAddress,
        address newSudoswapFactoryContractAddress,
        address newSudoswapRouterContractAddress
    ) public initializer {
        flashSellContractAddress = newFlashSellContractAddress; 
        sudoswapFactoryContractAddress = newSudoswapFactoryContractAddress;
        sudoswapRouterContractAddress = newSudoswapRouterContractAddress;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }

    /// @inheritdoc ISudoswapFlashSellIntegrationAdmin
    function updateFlashSellContractAddress(address newFlashSellContractAddress) external onlyOwner {
        require(address(newFlashSellContractAddress) != address(0), "00055");
        emit SudoswapFlashSellIntegrationXFlashSellContractAddressUpdated(
            flashSellContractAddress,
            newFlashSellContractAddress
        );
        flashSellContractAddress = newFlashSellContractAddress;
    }

    /// @inheritdoc ISudoswapFlashSellIntegrationAdmin
    function updateSudoswapFactoryContractAddress(address newSudoswapFactoryContractAddress) external onlyOwner {
        emit SudoswapFactoryContractAddressUpdated(newSudoswapFactoryContractAddress);
        sudoswapFactoryContractAddress = newSudoswapFactoryContractAddress;
    }

    /// @inheritdoc ISudoswapFlashSellIntegrationAdmin
    function updateSudoswapRouterContractAddress(address newSudoswapRouterContractAddress) external onlyOwner {
        emit SudoswapRouterContractAddressUpdated(newSudoswapRouterContractAddress);
        sudoswapRouterContractAddress = newSudoswapRouterContractAddress;
    }

    /// @inheritdoc ISudoswapFlashSellIntegrationAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc ISudoswapFlashSellIntegrationAdmin
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
    ) external payable override nonReentrant returns (bool) {
        _requireFlashSellContract();

        // decode data
        (ILSSVMPair lssvmPair) = abi.decode(data, (ILSSVMPair));

        // Sell the NFT
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = nftId;
        ILSSVMRouter.PairSwapSpecific[] memory pairSwapSpecific = new ILSSVMRouter.PairSwapSpecific[](1);
        pairSwapSpecific[0] = ILSSVMRouter.PairSwapSpecific({pair: lssvmPair, nftIds: nftIds});

        uint256 assetBalanceBefore = _getAssetBalance(address(loanAsset));

        // approve the NFT for Sudoswap Router
        IERC721Upgradeable(nftContractAddress).approve(sudoswapRouterContractAddress, nftId);
        // call router to execute swap
        ILSSVMRouter(sudoswapRouterContractAddress).swapNFTsForToken(
            pairSwapSpecific,
            loanAmount,
            address(this),
            block.timestamp
        );
        
        uint256 assetBalanceAfter = _getAssetBalance(address(loanAsset));

        if (loanAsset == address(0)) {
            // transfer the asset to FlashSell to allow settling the loan
            payable(flashSellContractAddress).sendValue(loanAmount);
            // transfer the remaining to the initiator
            payable(initiator).sendValue(assetBalanceAfter - assetBalanceBefore - loanAmount);
        } else {
            // transfer the asset to FlashSell to allow settling the loan
            IERC20Upgradeable(loanAsset).safeTransfer(flashSellContractAddress, loanAmount);
            // transfer the remaining to the initiator
            IERC20Upgradeable(loanAsset).safeTransfer(initiator, assetBalanceAfter - assetBalanceBefore - loanAmount);
        }
        return true;
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

    /// @notice This contract needs to accept ETH to acquire enough funds to purchase NFTs
    receive() external payable {}
}