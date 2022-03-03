//SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    mapping(address => AccountAssets) internal _accountAssets;

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
        assetToCAsset[asset] = cAsset;
        _cAssetToAsset[cAsset] = asset;

        emit newAssetWhitelisted(asset, cAsset);
    }

    // @notice returns the assets a depositor has deposited on NiftyApes.
    // @dev combined with cAssetBalances and/or utilizedCAssetBalances to calculate depositors total balance and total available balance.
    function getAssetsIn(address depositor) external view returns (address[] memory assetsIn) {
        assetsIn = _accountAssets[depositor].keys;
    }

    function getCAssetBalances(address account, address cAsset)
        external
        view
        returns (
            uint256 cAssetBalance,
            uint256 utilizedCAssetBalance,
            uint256 availableCAssetBalance
        )
    {
        cAssetBalance = _accountAssets[account].cAssetBalance[cAsset];
        utilizedCAssetBalance = _accountAssets[account].utilizedCAssetBalance[cAsset];
        availableCAssetBalance = cAssetBalance - utilizedCAssetBalance;
    }

    function getAvailableCAssetBalance(address account, address cAsset)
        public
        view
        returns (uint256 availableCAssetBalance)
    {
        availableCAssetBalance =
            _accountAssets[account].cAssetBalance[cAsset] -
            _accountAssets[account].utilizedCAssetBalance[cAsset];
    }

    function getCAssetBalancesAtIndex(address account, uint256 index)
        external
        view
        returns (
            uint256 cAssetBalance,
            uint256 utilizedCAssetBalance,
            uint256 availableCAssetBalance
        )
    {
        address asset = _accountAssets[account].keys[index];
        address cAsset = assetToCAsset[asset];

        cAssetBalance = _accountAssets[account].cAssetBalance[cAsset];
        utilizedCAssetBalance = _accountAssets[account].utilizedCAssetBalance[cAsset];
        availableCAssetBalance = cAssetBalance - utilizedCAssetBalance;
    }

    function accountAssetsSize(address account)
        external
        view
        returns (uint256 numberOfAccountAssets)
    {
        numberOfAccountAssets = _accountAssets[account].keys.length;
    }

    function addAssetToAccount(address account, address asset) internal {
        _accountAssets[account].inserted[asset] = true;
        _accountAssets[account].indexOf[asset] = _accountAssets[account].keys.length;
        _accountAssets[account].keys.push(asset);
    }

    function removeAssetFromAccount(address account, address asset) internal {
        delete _accountAssets[account].inserted[asset];

        uint256 index = _accountAssets[account].indexOf[asset];
        uint256 lastIndex = _accountAssets[account].keys.length - 1;
        address lastAsset = _accountAssets[account].keys[lastIndex];

        _accountAssets[account].indexOf[lastAsset] = index;
        delete _accountAssets[account].indexOf[asset];

        _accountAssets[account].keys[index] = lastAsset;
        _accountAssets[account].keys.pop();
    }

    // implement 10M limit for MVP

    // @notice returns number of cErc20 tokens added to balance
    function supplyErc20(address asset, uint256 numTokensToSupply) external returns (uint256) {
        require(assetToCAsset[asset] != address(0), "Asset not whitelisted on NiftyApes");

        address cAsset = assetToCAsset[asset];

        // Create a reference to the underlying asset contract, like DAI.
        IERC20 underlying = IERC20(asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        if (!_accountAssets[msg.sender].inserted[asset]) {
            addAssetToAccount(msg.sender, asset);
        }

        // transferFrom ERC20 from depositors address
        // review for safeTransferFrom
        require(
            underlying.transferFrom(msg.sender, address(this), numTokensToSupply),
            "underlying.transferFrom() failed"
        );

        require(underlying.approve(cAsset, numTokensToSupply), "underlying.approve() failed");

        uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();

        uint256 mintAmount = numTokensToSupply;

        (, uint256 mintTokens) = divScalarByExpTruncate(
            mintAmount,
            Exp({ mantissa: exchangeRateMantissa })
        );

        // Mint cTokens
        // Require a successful mint to proceed
        require(cToken.mint(numTokensToSupply) == 0, "cToken.mint() failed");

        // This state variable is written after external calls because external calls
        // add value or assets to this contract and this state variable could be re-entered to
        // increase balance, then withdrawing more funds than have been supplied.
        // updating the depositors cErc20 balance
        _accountAssets[msg.sender].cAssetBalance[cAsset] += mintTokens;

        emit Erc20Supplied(msg.sender, asset, numTokensToSupply);

        return mintTokens;
    }

    // @notice returns the number of CERC20 tokens added to balance
    // @dev takes the underlying asset address, not cAsset address
    //
    function supplyCErc20(address cAsset, uint256 numTokensToSupply) external returns (uint256) {
        require(_cAssetToAsset[cAsset] != address(0), "Asset not whitelisted on NiftyApes");

        address asset = _cAssetToAsset[cAsset];

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        if (!_accountAssets[msg.sender].inserted[asset]) {
            addAssetToAccount(msg.sender, asset);
        }

        // transferFrom ERC20 from depositors address
        require(
            cToken.transferFrom(msg.sender, address(this), numTokensToSupply),
            "cToken transferFrom failed"
        );

        // This state variable is written after external calls because external calls
        // add value or assets to this contract and this state variable could be re-entered to
        // increase balance, then withdrawing more funds than have been supplied.
        // updating the depositors cErc20 balance
        _accountAssets[msg.sender].cAssetBalance[cAsset] += numTokensToSupply;

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

        // Create a reference to the underlying asset contract, like DAI.
        IERC20 underlying = IERC20(asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        uint256 exchangeRateMantissa;
        uint256 redeemTokens;
        uint256 redeemAmount;

        exchangeRateMantissa = cToken.exchangeRateCurrent();

        (, redeemTokens) = divScalarByExpTruncate(
            amountToWithdraw,
            Exp({ mantissa: exchangeRateMantissa })
        );

        redeemAmount = amountToWithdraw;

        // require msg.sender has sufficient available balance of cErc20
        require(
            getAvailableCAssetBalance(msg.sender, cAsset) >= redeemTokens,
            "Must have sufficient balance"
        );

        _accountAssets[msg.sender].cAssetBalance[cAsset] -= redeemTokens;

        if (
            _accountAssets[msg.sender].cAssetBalance[cAsset] == 0 &&
            _accountAssets[msg.sender].utilizedCAssetBalance[cAsset] == 0
        ) {
            removeAssetFromAccount(msg.sender, asset);
        }

        // Retrieve your asset based on an amountToWithdraw of the asset
        require(cToken.redeemUnderlying(redeemAmount) == 0, "cToken.redeemUnderlying() failed");

        require(underlying.transfer(msg.sender, redeemAmount), "underlying.transfer() failed");

        emit Erc20Withdrawn(msg.sender, asset, amountToWithdraw);

        return redeemAmount;
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
            getAvailableCAssetBalance(msg.sender, cAsset) >= amountToWithdraw,
            "Must have an available balance greater than or equal to amountToWithdraw"
        );
        // updating the depositors cErc20 balance
        _accountAssets[msg.sender].cAssetBalance[cAsset] -= amountToWithdraw;

        if (
            _accountAssets[msg.sender].cAssetBalance[cAsset] == 0 &&
            _accountAssets[msg.sender].utilizedCAssetBalance[cAsset] == 0
        ) {
            removeAssetFromAccount(msg.sender, asset);
        }

        // transfer cErc20 tokens to depositor
        require(
            cToken.transfer(msg.sender, amountToWithdraw),
            "cToken.transfer failed. Have you approved the correct amount of Tokens"
        );

        emit CErc20Withdrawn(msg.sender, cAsset, amountToWithdraw);

        return amountToWithdraw;
    }

    function supplyEth() external payable returns (uint256) {
        address eth = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEth = assetToCAsset[eth];

        // Create a reference to the corresponding cToken contract
        ICEther cToken = ICEther(cEth);

        if (!_accountAssets[msg.sender].inserted[eth]) {
            addAssetToAccount(msg.sender, eth);
        }

        uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();

        (, uint256 mintTokens) = divScalarByExpTruncate(
            msg.value,
            Exp({ mantissa: exchangeRateMantissa })
        );

        // mint CEth tokens to this contract address
        // cEth mint() reverts on failure so do not need a require statement
        cToken.mint{ value: msg.value, gas: 250000 }();

        // This state variable is written after external calls because external calls
        // add value or assets to this contract and this state variable could be re-entered to
        // increase balance, then withdrawing more funds than have been supplied.
        // updating the depositors cErc20 balance
        // cAssetBalances[cEth][msg.sender] += mintTokens;
        _accountAssets[msg.sender].cAssetBalance[cEth] += mintTokens;

        emit EthSupplied(msg.sender, msg.value);

        return mintTokens;
    }

    function supplyCEth(uint256 numTokensToSupply) external returns (uint256) {
        address eth = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEth = assetToCAsset[eth];

        // Create a reference to the corresponding cToken contract
        ICEther cToken = ICEther(cEth);

        if (!_accountAssets[msg.sender].inserted[eth]) {
            addAssetToAccount(msg.sender, eth);
        }

        // transferFrom ERC20 from supplyers address
        require(
            cToken.transferFrom(msg.sender, address(this), numTokensToSupply),
            "cToken.transferFrom failed"
        );

        // This state variable is written after external calls because external calls
        // add value or assets to this contract and this state variable could be re-entered to
        // increase balance, then withdrawing more funds than have been supplied.
        // cAssetBalances[cEth][msg.sender] += numTokensToSupply;
        _accountAssets[msg.sender].cAssetBalance[cEth] += numTokensToSupply;

        emit CEthSupplied(msg.sender, numTokensToSupply);

        return numTokensToSupply;
    }

    function withdrawEth(uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address eth = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEth = assetToCAsset[eth];

        // Create a reference to the corresponding cToken contract, like cDAI
        ICEther cToken = ICEther(cEth);

        uint256 exchangeRateMantissa;
        uint256 redeemTokens;
        uint256 redeemAmount;
        exchangeRateMantissa = cToken.exchangeRateCurrent();

        (, redeemTokens) = divScalarByExpTruncate(
            amountToWithdraw,
            Exp({ mantissa: exchangeRateMantissa })
        );

        redeemAmount = amountToWithdraw;

        // require msg.sender has sufficient available balance of cEth
        require(
            getAvailableCAssetBalance(msg.sender, cEth) >= redeemTokens,
            "Must have sufficient balance"
        );

        _accountAssets[msg.sender].cAssetBalance[cEth] -= redeemTokens;

        if (
            _accountAssets[msg.sender].cAssetBalance[cEth] == 0 &&
            _accountAssets[msg.sender].utilizedCAssetBalance[cEth] == 0
        ) {
            removeAssetFromAccount(msg.sender, eth);
        }

        // Retrieve your asset based on an amountToWithdraw of the asset
        require(cToken.redeemUnderlying(redeemAmount) == 0, "cToken.redeemUnderlying() failed");

        // Repay eth to depositor
        (bool success, ) = (msg.sender).call{ value: redeemAmount }("");
        require(success, "Send eth to depositor failed");

        emit EthWithdrawn(msg.sender, amountToWithdraw);

        return redeemAmount;
    }

    function withdrawCEth(uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address eth = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEth = assetToCAsset[eth];

        // Create a reference to the corresponding cToken contract, like cDAI
        ICEther cToken = ICEther(cEth);

        // require msg.sender has sufficient available balance of cEth
        require(
            getAvailableCAssetBalance(msg.sender, cEth) >= amountToWithdraw,
            "Must have an available balance greater than or equal to amountToWithdraw"
        );

        // updating the depositors cErc20 balance
        _accountAssets[msg.sender].cAssetBalance[cEth] -= amountToWithdraw;

        if (
            _accountAssets[msg.sender].cAssetBalance[cEth] == 0 &&
            _accountAssets[msg.sender].utilizedCAssetBalance[cEth] == 0
        ) {
            removeAssetFromAccount(msg.sender, eth);
        }

        // transfer cErc20 tokens to depositor
        require(
            cToken.transfer(msg.sender, amountToWithdraw),
            "cToken.transfer failed. Have you approved the correct amount of Tokens"
        );

        emit CEthWithdrawn(msg.sender, amountToWithdraw);

        return amountToWithdraw;
    }
}
