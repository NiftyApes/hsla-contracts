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

    function getCAssetBalance(address account, address cAsset)
        public
        view
        returns (uint256 cAssetBalance)
    {
        return _accountAssets[account][cAsset].cAssetBalance;
    }

    // implement 10M limit for MVP

    // @notice returns number of cErc20 tokens added to balance
    function supplyErc20(address asset, uint256 numTokensToSupply) external returns (uint256) {
        require(assetToCAsset[asset] != address(0), "Asset not whitelisted on NiftyApes");

        address cAsset = assetToCAsset[asset];

        uint256 cTokensMinted = mintCErc20(msg.sender, address(this), asset, numTokensToSupply);

        // This state variable is written after external calls because external calls
        // add value or assets to this contract and this state variable could be re-entered to
        // increase balance, then withdrawing more funds than have been supplied.
        // updating the depositors cErc20 balance
        _accountAssets[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        emit Erc20Supplied(msg.sender, asset, numTokensToSupply);

        return cTokensMinted;
    }

    // @notice returns the number of CERC20 tokens added to balance
    // @dev takes the underlying asset address, not cAsset address
    //
    function supplyCErc20(address cAsset, uint256 numTokensToSupply) external returns (uint256) {
        require(_cAssetToAsset[cAsset] != address(0), "Asset not whitelisted on NiftyApes");

        address asset = _cAssetToAsset[cAsset];

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // transferFrom ERC20 from depositors address
        require(
            cToken.transferFrom(msg.sender, address(this), numTokensToSupply),
            "cToken transferFrom failed"
        );

        // This state variable is written after external calls because external calls
        // add value or assets to this contract and this state variable could be re-entered to
        // increase balance, then withdrawing more funds than have been supplied.
        // updating the depositors cErc20 balance
        _accountAssets[msg.sender][cAsset].cAssetBalance += numTokensToSupply;

        emit CErc20Supplied(msg.sender, cAsset, numTokensToSupply);

        return numTokensToSupply;
    }

    // True to withdraw based on cErc20 amount. False to withdraw based on amount of underlying erc20
    function withdrawErc20(address asset, uint256 amountToWithdraw)
        public
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(assetToCAsset[asset] != address(0), "Asset not whitelisted on NiftyApes");

        address cAsset = assetToCAsset[asset];

        IERC20 underlying = IERC20(asset);

        uint256 cTokensBurnt = burnCErc20(asset, amountToWithdraw);

        // require msg.sender has sufficient available balance of cErc20
        require(
            getCAssetBalance(msg.sender, cAsset) >= cTokensBurnt,
            "Must have sufficient balance"
        );

        _accountAssets[msg.sender][cAsset].cAssetBalance -= cTokensBurnt;

        require(underlying.transfer(msg.sender, amountToWithdraw), "underlying.transfer() failed");

        emit Erc20Withdrawn(msg.sender, asset, amountToWithdraw);

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
        require(cToken.mint(amount) == 0, "cToken.mint() failed");
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
        require(cToken.redeemUnderlying(amount) == 0, "cToken.redeemUnderlying() failed");
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
}
