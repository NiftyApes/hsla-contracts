//SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    // @notice By calling 'revert' in the fallback function, we prevent anyone
    //         from accidentally sending ether directly to this contract.
    fallback() external payable {
        revert();
    }

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

    // @notice returns number of cErc20 tokens added to balance
    function supplyErc20(address asset, uint256 numTokensToSupply) external returns (uint256) {
        address cAsset = getCAsset(asset);

        uint256 cTokensMinted = mintCErc20(msg.sender, address(this), asset, numTokensToSupply);

        _accountAssets[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        emit Erc20Supplied(msg.sender, asset, numTokensToSupply, cTokensMinted);

        return cTokensMinted;
    }

    // @notice returns the number of CERC20 tokens added to balance
    // @dev takes the underlying asset address, not cAsset address
    //
    function supplyCErc20(address cAsset, uint256 cTokenAmount) external returns (uint256) {
        getAsset(cAsset); // Ensures asset / cAsset is in the allow list
        ICERC20 cToken = ICERC20(cAsset);

        require(
            cToken.transferFrom(msg.sender, address(this), cTokenAmount),
            "cToken transferFrom failed"
        );

        _accountAssets[msg.sender][cAsset].cAssetBalance += cTokenAmount;

        emit CErc20Supplied(msg.sender, cAsset, cTokenAmount);

        return cTokenAmount;
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

        require(underlying.transfer(msg.sender, amountToWithdraw), "underlying.transfer() failed");

        emit Erc20Withdrawn(msg.sender, asset, amountToWithdraw, cTokensBurnt);

        return cTokensBurnt;
    }

    function withdrawCErc20(address cAsset, uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(_cAssetToAsset[cAsset] != address(0), "Asset not whitelisted");

        address asset = _cAssetToAsset[cAsset];

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // require msg.sender has sufficient available balance of cErc20
        require(
            getCAssetBalance(msg.sender, cAsset) >= amountToWithdraw,
            "Must have an available balance greater than or equal to amountToWithdraw"
        );
        // updating the depositors cErc20 balance
        _accountAssets[msg.sender][cAsset].cAssetBalance -= amountToWithdraw;

        // transfer cErc20 tokens to depositor
        require(
            cToken.transfer(msg.sender, amountToWithdraw),
            "cToken.transfer failed. Have you approved the correct amount of Tokens"
        );

        emit CErc20Withdrawn(msg.sender, cAsset, amountToWithdraw);

        return amountToWithdraw;
    }

    function supplyEth() external payable returns (uint256) {
        uint256 cTokensMinted = mintCEth(msg.value);

        _accountAssets[msg.sender][assetToCAsset[ETH_ADDRESS]].cAssetBalance += cTokensMinted;

        emit EthSupplied(msg.sender, msg.value);

        return cTokensMinted;
    }

    function withdrawEth(uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cEth = assetToCAsset[ETH_ADDRESS];
        uint256 cTokensBurnt = burnCErc20(ETH_ADDRESS, amountToWithdraw);

        // require msg.sender has sufficient available balance of cEth
        require(getCAssetBalance(msg.sender, cEth) >= cTokensBurnt, "Must have sufficient balance");
        _accountAssets[msg.sender][cEth].cAssetBalance -= cTokensBurnt;

        Address.sendValue(payable(msg.sender), amountToWithdraw);

        emit EthWithdrawn(msg.sender, amountToWithdraw);

        return cTokensBurnt;
    }

    function mintCErc20(
        address from,
        address to,
        address asset,
        uint256 amount
    ) internal returns (uint256) {
        address cAsset = assetToCAsset[asset];
        // TODO(dankurka): Maybe check?
        IERC20 underlying = IERC20(asset);
        ICERC20 cToken = ICERC20(cAsset);

        require(
            underlying.transferFrom(from, to, amount) == true,
            "underlying.transferFrom() failed"
        );

        require(underlying.approve(cAsset, amount) == true, "underlying.approve() failed");

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
        // TODO(dankurka): Maybe check?
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
