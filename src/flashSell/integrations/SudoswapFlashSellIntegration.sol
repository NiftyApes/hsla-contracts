//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "../../interfaces/flashSellIntegrations/sudoswapFlashSellIntegration/ISudoswapFlashSellIntegration.sol";
import "../../interfaces/sudoswap/ILSSVMPairFactoryLike.sol";
import "../../interfaces/sudoswap/ILSSVMPair.sol";
import "../../interfaces/sudoswap/ILSSVMRouter.sol";
import "../base/FlashSellIntegrationBase.sol";

/// @notice Integration of Sudoswap to FlashSell to allow sale of NFTs to settle the active loans
contract SudoswapFlashSellIntegration is
    PausableUpgradeable,
    ISudoswapFlashSellIntegration,
    FlashSellIntegrationBase
{
    /// @inheritdoc ISudoswapFlashSellIntegration
    address public sudoswapFactoryContractAddress;
    
    /// @inheritdoc ISudoswapFlashSellIntegration
    address public sudoswapRouterContractAddress;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the marketplace integration contract.
    function initialize() public override initializer {
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
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

    function _executeTheSale(
        address nftContractAddress,
        uint256 nftId,
        address loanAsset,
        uint256 loanAmount,
        bytes calldata data
    ) internal override {
        // decode data
        (ILSSVMPair lssvmPair) = abi.decode(data, (ILSSVMPair));

        // require pair token same as loanAsset
        _requireValidPairAsset(lssvmPair, loanAsset);

        // Sell the NFT
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = nftId;
        ILSSVMRouter.PairSwapSpecific[] memory pairSwapSpecific = new ILSSVMRouter.PairSwapSpecific[](1);
        pairSwapSpecific[0] = ILSSVMRouter.PairSwapSpecific({pair: lssvmPair, nftIds: nftIds});

        // approve the NFT for Sudoswap Router
        IERC721Upgradeable(nftContractAddress).approve(sudoswapRouterContractAddress, nftId);
        // call router to execute swap
        ILSSVMRouter(sudoswapRouterContractAddress).swapNFTsForToken(
            pairSwapSpecific,
            loanAmount,
            address(this),
            block.timestamp
        );
    }

    function _requireValidPairAsset(ILSSVMPair lssvmPair, address loanAsset) private pure {
        ILSSVMPairFactoryLike.PairVariant pairVariant = lssvmPair.pairVariant();
        address pairAsset;
        if (pairVariant == ILSSVMPairFactoryLike.PairVariant.ENUMERABLE_ERC20 || pairVariant == ILSSVMPairFactoryLike.PairVariant.MISSING_ENUMERABLE_ERC20) {
            pairAsset = address(lssvmPair.token());
        }
        require(loanAsset == pairAsset, "00050");
    }

    /// @notice This contract needs to accept ETH to acquire enough funds to purchase NFTs
    receive() external payable {}
}