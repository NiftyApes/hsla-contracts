//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "./interfaces/compound/ICEther.sol";
import "./interfaces/compound/ICERC20.sol";
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./interfaces/niftyapes/liquidity/ILiquidityAdmin.sol";
import "./lib/Math.sol";

/// @title Implemention of the INiftyApes interface
contract Liquidity is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ILiquidity,
    ILiquidityAdmin
{
    using ECDSAUpgradeable for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    /// @notice The account balance for each asset of a user
    mapping(address => mapping(address => Balance)) internal _balanceByAccountByAsset;

    /// @inheritdoc ILiquidity
    mapping(address => uint256) public override maxBalanceByCAsset;

    /// @dev Internal address used for for ETH in our mappings
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @inheritdoc ILiquidity
    mapping(address => address) public override assetToCAsset;

    /// @notice The reverse mapping for assetToCAsset
    mapping(address => address) internal _cAssetToAsset;

    function initialize(address _liquidity) public initializer {
        // TODO
    }

    /// @inheritdoc ILiquidityAdmin
    function setCAssetAddress(address asset, address cAsset) external onlyOwner {
        require(assetToCAsset[asset] == address(0), "asset already set");
        require(_cAssetToAsset[cAsset] == address(0), "casset already set");
        assetToCAsset[asset] = cAsset;
        _cAssetToAsset[cAsset] = asset;

        emit NewAssetListed(asset, cAsset);
    }

    /// @inheritdoc ILiquidityAdmin
    function setMaxCAssetBalance(address asset, uint256 maxBalance) external onlyOwner {
        maxBalanceByCAsset[getCAsset(asset)] = maxBalance;
    }

    /// @inheritdoc ILiquidityAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc ILiquidityAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc ILiquidity
    function getCAssetBalance(address account, address cAsset) public view returns (uint256) {
        return _balanceByAccountByAsset[account][cAsset].cAssetBalance;
    }

    /// @inheritdoc ILiquidity
    function supplyErc20(address asset, uint256 tokenAmount)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cAsset = getCAsset(asset);

        uint256 cTokensMinted = mintCErc20(msg.sender, address(this), asset, tokenAmount);

        _balanceByAccountByAsset[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        requireMaxCAssetBalance(cAsset);

        emit Erc20Supplied(msg.sender, asset, tokenAmount, cTokensMinted);

        return cTokensMinted;
    }

    /// @inheritdoc ILiquidity
    function supplyCErc20(address cAsset, uint256 cTokenAmount)
        external
        whenNotPaused
        nonReentrant
    {
        getAsset(cAsset); // Ensures asset / cAsset is in the allow list
        IERC20Upgradeable cToken = IERC20Upgradeable(cAsset);

        cToken.safeTransferFrom(msg.sender, address(this), cTokenAmount);

        _balanceByAccountByAsset[msg.sender][cAsset].cAssetBalance += cTokenAmount;

        requireMaxCAssetBalance(cAsset);

        emit CErc20Supplied(msg.sender, cAsset, cTokenAmount);
    }

    /// @inheritdoc ILiquidity
    function withdrawErc20(address asset, uint256 tokenAmount)
        public
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cAsset = getCAsset(asset);
        IERC20Upgradeable underlying = IERC20Upgradeable(asset);

        uint256 cTokensBurnt = burnCErc20(asset, tokenAmount);

        withdrawCBalance(msg.sender, cAsset, cTokensBurnt);

        underlying.safeTransfer(msg.sender, tokenAmount);

        emit Erc20Withdrawn(msg.sender, asset, tokenAmount, cTokensBurnt);

        return cTokensBurnt;
    }

    /// @inheritdoc ILiquidity
    function withdrawCErc20(address cAsset, uint256 cTokenAmount)
        external
        whenNotPaused
        nonReentrant
    {
        // Making sure a mapping for cAsset exists
        getAsset(cAsset);
        IERC20Upgradeable cToken = IERC20Upgradeable(cAsset);

        withdrawCBalance(msg.sender, cAsset, cTokenAmount);

        cToken.safeTransfer(msg.sender, cTokenAmount);

        emit CErc20Withdrawn(msg.sender, cAsset, cTokenAmount);
    }

    /// @inheritdoc ILiquidity
    function supplyEth() external payable whenNotPaused nonReentrant returns (uint256) {
        address cAsset = getCAsset(ETH_ADDRESS);

        uint256 cTokensMinted = mintCEth(msg.value);

        _balanceByAccountByAsset[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        requireMaxCAssetBalance(cAsset);

        emit EthSupplied(msg.sender, msg.value, cTokensMinted);

        return cTokensMinted;
    }

    /// @inheritdoc ILiquidity
    function withdrawEth(uint256 amount) external whenNotPaused nonReentrant returns (uint256) {
        address cAsset = getCAsset(ETH_ADDRESS);
        uint256 cTokensBurnt = burnCErc20(ETH_ADDRESS, amount);

        withdrawCBalance(msg.sender, cAsset, cTokensBurnt);

        payable(msg.sender).sendValue(amount);

        emit EthWithdrawn(msg.sender, amount, cTokensBurnt);

        return cTokensBurnt;
    }

    function getCAsset(address asset) public view returns (address) {
        address cAsset = assetToCAsset[asset];
        require(cAsset != address(0), "asset allow list");
        require(asset == _cAssetToAsset[cAsset], "non matching allow list");
        return cAsset;
    }

    function getAsset(address cAsset) public view returns (address) {
        address asset = _cAssetToAsset[cAsset];
        require(asset != address(0), "cAsset allow list");
        require(cAsset == assetToCAsset[asset], "non matching allow list");
        return asset;
    }

    // TODO admin
    function withdrawCBalance(
        address account,
        address cAsset,
        uint256 cTokenAmount
    ) public {
        requireCAssetBalance(account, cAsset, cTokenAmount);
        _balanceByAccountByAsset[account][cAsset].cAssetBalance -= cTokenAmount;
    }

    // TODO admin
    function addCBalance(
        address account,
        address cAsset,
        uint256 cTokenAmount
    ) public {
        _balanceByAccountByAsset[account][cAsset].cAssetBalance += cTokenAmount;
    }

    // This is needed to receive ETH when calling withdrawing ETH from compund
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function requireMaxCAssetBalance(address cAsset) internal view {
        uint256 maxCAssetBalance = maxBalanceByCAsset[cAsset];
        if (maxCAssetBalance != 0) {
            require(maxCAssetBalance >= ICERC20(cAsset).balanceOf(address(this)), "max casset");
        }
    }

    // TODO admin
    function mintCErc20(
        address from,
        address to,
        address asset,
        uint256 amount
    ) public returns (uint256) {
        address cAsset = assetToCAsset[asset];
        IERC20Upgradeable underlying = IERC20Upgradeable(asset);
        ICERC20 cToken = ICERC20(cAsset);

        underlying.safeTransferFrom(from, to, amount);
        underlying.safeIncreaseAllowance(cAsset, amount);

        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        require(cToken.mint(amount) == 0, "cToken mint");
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceAfter - cTokenBalanceBefore;
    }

    // TODO admin
    function mintCEth(uint256 amount) public returns (uint256) {
        address cAsset = assetToCAsset[ETH_ADDRESS];
        ICEther cToken = ICEther(cAsset);
        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        cToken.mint{ value: amount }();
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceAfter - cTokenBalanceBefore;
    }

    // TODO admin
    function burnCErc20(address asset, uint256 amount) public returns (uint256) {
        address cAsset = assetToCAsset[asset];
        ICERC20 cToken = ICERC20(cAsset);

        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        require(cToken.redeemUnderlying(amount) == 0, "redeemUnderlying failed");
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceBefore - cTokenBalanceAfter;
    }

    function requireCAssetBalance(
        address account,
        address cAsset,
        uint256 amount
    ) public view {
        require(getCAssetBalance(account, cAsset) >= amount, "Insufficient cToken balance");
    }
}
