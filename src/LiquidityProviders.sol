//SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/compound/ICERC20.sol";
import "./interfaces/compound/ICEther.sol";
import "./ErrorReporter.sol";
import "./Exponential.sol";
import "./interfaces/ILiquidityProviders.sol";

// @title An interface for liquidity providers to supply and withdraw tokens
// @author Captnseagraves
// @contributors Alcibiades
// @notice This contract wraps and unwraps, tracks balances of deposited Assets and cAssets

// TODO document reentrancy bugs for auditors
// TODO Implement a proxy

contract LiquidityProviders is
    ILiquidityProviders,
    Exponential,
    Ownable,
    Pausable,
    ReentrancyGuard,
    TokenErrorReporter
{
    using SafeERC20 for IERC20;
    // ---------- STATE VARIABLES --------------- //

    // Mapping of assetAddress to cAssetAddress
    // controls assets available for deposit on NiftyApes
    mapping(address => address) public assetToCAsset;
    // Reverse mapping of assetAddress to cAssetAddress
    mapping(address => address) internal _cAssetToAsset;

    mapping(address => mapping(address => Balance)) internal _accountAssets;

    address constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // ---------- FUNCTIONS -------------- //

    // This is needed to receive ETH when calling `withdrawEth`
    receive() external payable {}

    // @notice Sets an asset as allowed on the platform and creates asset => cAsset mapping
    function setCAssetAddress(address asset, address cAsset) external onlyOwner {
        require(assetToCAsset[asset] == address(0), "asset already set");
        require(_cAssetToAsset[cAsset] == address(0), "casset already set");
        assetToCAsset[asset] = cAsset;
        _cAssetToAsset[cAsset] = asset;

        emit NewAssetWhitelisted(asset, cAsset);
    }

    function getCAssetBalance(address account, address cAsset) public view returns (uint256) {
        return _accountAssets[account][cAsset].cAssetBalance;
    }

    // implement 10M limit for MVP

    function supplyErc20(address asset, uint256 numTokensToSupply)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cAsset = getCAsset(asset);

        uint256 cTokensMinted = mintCErc20(msg.sender, address(this), asset, numTokensToSupply);

        _accountAssets[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        emit Erc20Supplied(msg.sender, asset, numTokensToSupply, cTokensMinted);

        return cTokensMinted;
    }

    function supplyCErc20(address cAsset, uint256 cTokenAmount)
        external
        whenNotPaused
        nonReentrant
    {
        getAsset(cAsset); // Ensures asset / cAsset is in the allow list
        IERC20 cToken = IERC20(cAsset);

        cToken.safeTransferFrom(msg.sender, address(this), cTokenAmount);

        _accountAssets[msg.sender][cAsset].cAssetBalance += cTokenAmount;

        emit CErc20Supplied(msg.sender, cAsset, cTokenAmount);
    }

    function withdrawErc20(address asset, uint256 amountToWithdraw)
        public
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cAsset = getCAsset(asset);
        IERC20 underlying = IERC20(asset);

        uint256 cTokensBurnt = burnCErc20(asset, amountToWithdraw);

        withdrawCBalance(msg.sender, cAsset, cTokensBurnt);

        underlying.safeTransfer(msg.sender, amountToWithdraw);

        emit Erc20Withdrawn(msg.sender, asset, amountToWithdraw, cTokensBurnt);

        return cTokensBurnt;
    }

    function withdrawCErc20(address cAsset, uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
    {
        address asset = getAsset(cAsset);
        IERC20 cToken = IERC20(cAsset);

        withdrawCBalance(msg.sender, cAsset, amountToWithdraw);

        cToken.safeTransfer(msg.sender, amountToWithdraw);

        emit CErc20Withdrawn(msg.sender, cAsset, amountToWithdraw);
    }

    function supplyEth() external payable whenNotPaused nonReentrant returns (uint256) {
        address cAsset = getCAsset(ETH_ADDRESS);

        uint256 cTokensMinted = mintCEth(msg.value);

        _accountAssets[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        emit EthSupplied(msg.sender, msg.value, cTokensMinted);

        return cTokensMinted;
    }

    function withdrawEth(uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cAsset = getCAsset(ETH_ADDRESS);
        uint256 cTokensBurnt = burnCErc20(ETH_ADDRESS, amountToWithdraw);

        withdrawCBalance(msg.sender, cAsset, cTokensBurnt);

        Address.sendValue(payable(msg.sender), amountToWithdraw);

        emit EthWithdrawn(msg.sender, amountToWithdraw, cTokensBurnt);

        return cTokensBurnt;
    }

    function mintCErc20(
        address from,
        address to,
        address asset,
        uint256 amount
    ) internal returns (uint256) {
        address cAsset = assetToCAsset[asset];
        IERC20 underlying = IERC20(asset);
        ICERC20 cToken = ICERC20(cAsset);

        underlying.safeTransferFrom(from, to, amount);
        underlying.safeIncreaseAllowance(cAsset, amount);

        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        require(cToken.mint(amount) == 0, "cToken mint");
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceAfter - cTokenBalanceBefore;
    }

    function mintCEth(uint256 amount) internal returns (uint256) {
        address cAsset = assetToCAsset[ETH_ADDRESS];
        ICEther cToken = ICEther(cAsset);
        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        cToken.mint{ value: amount }();
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceAfter - cTokenBalanceBefore;
    }

    function burnCErc20(address asset, uint256 amount) internal returns (uint256) {
        address cAsset = assetToCAsset[asset];
        ICERC20 cToken = ICERC20(cAsset);

        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        require(cToken.redeemUnderlying(amount) == 0, "redeemUnderlying failed");
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceBefore - cTokenBalanceAfter;
    }

    function assetAmountToCAssetAmount(address asset, uint256 amount) internal returns (uint256) {
        address cAsset = assetToCAsset[asset];
        ICERC20 cToken = ICERC20(cAsset);

        uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();

        (MathError mathError, uint256 amountCTokens) = divScalarByExpTruncate(
            amount,
            Exp({ mantissa: exchangeRateMantissa })
        );

        require(mathError == MathError.NO_ERROR, "Math failed");

        return amountCTokens;
    }

    function getCAsset(address asset) internal view returns (address) {
        address cAsset = assetToCAsset[asset];
        require(cAsset != address(0), "asset allow list");
        require(asset == _cAssetToAsset[cAsset], "non matching allow list");
        return cAsset;
    }

    function getAsset(address cAsset) internal view returns (address) {
        address asset = _cAssetToAsset[cAsset];
        require(asset != address(0), "cAsset allow list");
        require(cAsset == assetToCAsset[asset], "non matching allow list");
        return asset;
    }

    function withdrawCBalance(
        address account,
        address cAsset,
        uint256 cTokenAmount
    ) internal {
        require(getCAssetBalance(account, cAsset) >= cTokenAmount, "Insuffient ctoken balance");
        _accountAssets[account][cAsset].cAssetBalance -= cTokenAmount;
    }
}
