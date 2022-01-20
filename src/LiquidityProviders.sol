//SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/compound/ICERC20.sol";
import "./interfaces/compound/ICEther.sol";
import "./ErrorReporter.sol";
import "./Exponential.sol";
import "./interfaces/ILiquidityProviders.sol";

// TODO(need to implement Proxy and Intitializable contracts?)

// @title An interface for liquidity providers to supply and withdraw tokens
// @author Kevin Seagraves
// @notice This contract wraps and unwraps, tracks balances of deposited Assets and cAssets
// TODO(Factor out Exponential to library)
contract LiquidityProviders is
    ILiquidityProviders,
    Exponential,
    Ownable,
    Pausable,
    ReentrancyGuard,
    TokenErrorReporter
{
    // Solidity 0.8.x provides safe math, but uses an invalid opcode error which consumes all gas. SafeMath uses revert which returns all gas.
    using SafeMath for uint256;

    // ---------- STATE VARIABLES --------------- //

    // Mapping of assetAddress to cAssetAddress
    // controls assets available for deposit on NiftyApes
    mapping(address => address) public assetToCAsset;
    // Reverse mapping of assetAddress to cAssetAddress
    mapping(address => address) internal _cAssetToAsset;

    // TODO(These could be combined into a struct for gas savings)
    // Mapping of cAssetBalance to cAssetAddress to depositor address
    mapping(address => mapping(address => uint256)) public cAssetBalances;

    // Mapping of cAssetBalance to cAssetAddress to depositor address
    mapping(address => mapping(address => uint256))
        public utilizedCAssetBalances;

    /**
     * @notice Mapping of allCAssetsEntered to depositorAddress
     */
    // TODO(This could be obviated with iterable mapping and reversing input order tuple for cAssetBalances)
    mapping(address => address[]) internal accountAssets;

    // ---------- FUNCTIONS -------------- //

    // This is needed to receive ETH when calling `withdrawEth`
    receive() external payable {}

    // @notice By calling 'revert' in the fallback function, we prevent anyone
    //         from accidentally sending ether directly to this contract.
    fallback() external payable {
        revert();
    }

    // @notice returns the assets a depositor has deposited on NiftyApes.
    // @dev combined with cAssetBalances and/or utilizedCAssetBalances to calculate depositors total balance and total available balance.
    function getAssetsIn(address depositor)
        external
        view
        returns (address[] memory)
    {
        address[] memory assetsIn = accountAssets[depositor];

        return assetsIn;
    }

    // @notice Sets an asset as allowed on the platform and creates asset => cAsset mapping
    function setCAssetAddress(address asset, address cAsset)
        external
        onlyOwner
    {
        assetToCAsset[asset] = cAsset;
        _cAssetToAsset[cAsset] = asset;

        emit newAssetWhitelisted(asset, cAsset);
    }

    // @notice returns number of cErc20 tokens added to balance
    function supplyErc20(address asset, uint256 numTokensToSupply)
        external
        returns (uint256)
    {
        require(
            assetToCAsset[asset] != address(0),
            "Asset not whitelisted on NiftyApes"
        );

        address cAsset = assetToCAsset[asset];

        // Create a reference to the underlying asset contract, like DAI.
        IERC20 underlying = IERC20(asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // transferFrom ERC20 from depositors address
        require(
            underlying.transferFrom(
                msg.sender,
                address(this),
                numTokensToSupply
            ) == true,
            "underlying.transferFrom() failed"
        );

        // Approve transfer on the ERC20 contract from LiquidityProviders contract
        underlying.approve(cAsset, numTokensToSupply);

        // calculate expectedAmountToBeMinted. This is the same conversion math performed in cToken.mint()
        MintLocalVars memory vars;

        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        vars.mintAmount = numTokensToSupply;

        (vars.mathErr, vars.mintTokens) = divScalarByExpTruncate(
            vars.mintAmount,
            Exp({mantissa: vars.exchangeRateMantissa})
        );

        // Mint cTokens
        // Require a successful mint to proceed
        require(cToken.mint(numTokensToSupply) == 0, "cToken.mint() failed");

        // updating the depositors cErc20 balance
        cAssetBalances[cAsset][msg.sender] += vars.mintTokens;

        emit Erc20Supplied(msg.sender, asset, numTokensToSupply);

        return vars.mintTokens;
    }

    // @notice returns the number of CERC20 tokens added to balance
    // @dev takes the underlying asset address, not cAsset address
    //
    function supplyCErc20(address cAsset, uint256 numTokensToSupply)
        external
        returns (uint256)
    {
        require(
            _cAssetToAsset[cAsset] != address(0),
            "Asset not whitelisted on NiftyApes"
        );

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // transferFrom ERC20 from depositors address
        require(
            cToken.transferFrom(msg.sender, address(this), numTokensToSupply) ==
                true,
            "cToken transferFrom failed. Have you approved the correct amount of Tokens?"
        );

        // updating the depositors cErc20 balance
        cAssetBalances[cAsset][msg.sender] += numTokensToSupply;

        emit CErc20Supplied(msg.sender, cAsset, numTokensToSupply);

        return numTokensToSupply;
    }

    // True to withdraw based on cErc20 amount. False to withdraw based on amount of underlying erc20
    function withdrawErc20(
        address asset,
        bool redeemType,
        uint256 amountToWithdraw
    ) public whenNotPaused nonReentrant returns (uint256) {
        require(
            assetToCAsset[asset] != address(0),
            "Asset not whitelisted on NiftyApes"
        );

        address cAsset = assetToCAsset[asset];

        // Create a reference to the underlying asset contract, like DAI.
        IERC20 underlying = IERC20(asset);

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // redeemType == true >> withdraw based on amount of cErc20
        if (redeemType == true) {
            RedeemLocalVars memory vars;

            vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

            vars.redeemTokens = amountToWithdraw;

            (vars.mathErr, vars.redeemAmount) = mulScalarTruncate(
                Exp({mantissa: vars.exchangeRateMantissa}),
                amountToWithdraw
            );
            if (vars.mathErr != MathError.NO_ERROR) {
                return
                    failOpaque(
                        Error.MATH_ERROR,
                        FailureInfo.REDEEM_EXCHANGE_TOKENS_CALCULATION_FAILED,
                        uint256(vars.mathErr)
                    );
            }

            // require msg.sender has sufficient available balance of cErc20
            require(
                (cAssetBalances[cAsset][msg.sender] -
                    utilizedCAssetBalances[cAsset][msg.sender]) >=
                    vars.redeemTokens,
                "Must have an available balance greater than or equal to amountToWithdraw"
            );

            cAssetBalances[cAsset][msg.sender] -= vars.redeemTokens;

            // Retrieve your asset based on an amountToWithdraw of the asset
            require(
                cToken.redeemUnderlying(vars.redeemAmount) == 0,
                "cToken.redeemUnderlying failed"
            );

            require(
                underlying.transfer(msg.sender, vars.redeemAmount) == true,
                "underlying.transfer() failed"
            );

            // redeemType == false >> withdraw based on amount of underlying
        } else {
            RedeemLocalVars memory vars;

            vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

            (vars.mathErr, vars.redeemTokens) = divScalarByExpTruncate(
                amountToWithdraw,
                Exp({mantissa: vars.exchangeRateMantissa})
            );
            if (vars.mathErr != MathError.NO_ERROR) {
                return
                    failOpaque(
                        Error.MATH_ERROR,
                        FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                        uint256(vars.mathErr)
                    );
            }

            vars.redeemAmount = amountToWithdraw;

            // require msg.sender has sufficient available balance of cErc20
            require(
                (cAssetBalances[cAsset][msg.sender] -
                    utilizedCAssetBalances[cAsset][msg.sender]) >=
                    vars.redeemTokens,
                "Must have an available balance greater than or equal to amountToWithdraw"
            );

            cAssetBalances[cAsset][msg.sender] -= vars.redeemTokens;

            // Retrieve your asset based on an amountToWithdraw of the asset
            require(
                cToken.redeemUnderlying(vars.redeemAmount) == 0,
                "cToken.redeemUnderlying() failed"
            );

            require(
                underlying.transfer(msg.sender, vars.redeemAmount) == true,
                "underlying.transfer() failed"
            );
        }

        emit Erc20Withdrawn(msg.sender, asset, redeemType, amountToWithdraw);

        return 0;
    }

    function withdrawCErc20(address cAsset, uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(
            _cAssetToAsset[cAsset] != address(0),
            "Asset not whitelisted on NiftyApes"
        );

        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(cAsset);

        // require msg.sender has sufficient available balance of cErc20
        require(
            (cAssetBalances[cAsset][msg.sender] -
                utilizedCAssetBalances[cAsset][msg.sender]) >= amountToWithdraw,
            "Must have an available balance greater than or equal to amountToWithdraw"
        );
        // updating the depositors cErc20 balance
        cAssetBalances[cAsset][msg.sender] -= amountToWithdraw;

        // transfer cErc20 tokens to depositor
        require(
            cToken.transfer(msg.sender, amountToWithdraw) == true,
            "cToken.transfer failed. Have you approved the correct amount of Tokens"
        );

        emit CErc20Withdrawn(msg.sender, cAsset, amountToWithdraw);

        return amountToWithdraw;
    }

    function supplyEth() external payable returns (uint256) {
        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEtherContract = assetToCAsset[
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ];

        // Create a reference to the corresponding cToken contract
        ICEther cToken = ICEther(cEtherContract);

        // calculate expectedAmountToBeMinted
        MintLocalVars memory vars;

        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        (vars.mathErr, vars.mintTokens) = divScalarByExpTruncate(
            msg.value,
            Exp({mantissa: vars.exchangeRateMantissa})
        );

        // mint CEth tokens to this contract address
        // cEth mint() reverts on failure so do not need a require statement
        cToken.mint{value: msg.value, gas: 250000}();

        // updating the depositors cErc20 balance
        cAssetBalances[cEtherContract][msg.sender] += vars.mintTokens;

        emit EthSupplied(msg.sender, msg.value);

        return vars.mintTokens;
    }

    function supplyCEth(uint256 numTokensToSupply) external returns (uint256) {
        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEtherContract = assetToCAsset[
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ];

        // Create a reference to the corresponding cToken contract
        ICEther cToken = ICEther(cEtherContract);

        // transferFrom ERC20 from supplyers address
        require(
            cToken.transferFrom(msg.sender, address(this), numTokensToSupply) ==
                true,
            "cToken.transferFrom failed"
        );

        cAssetBalances[cEtherContract][msg.sender] += numTokensToSupply;

        emit CEthSupplied(msg.sender, numTokensToSupply);

        return numTokensToSupply;
    }

    // True to withdraw based on cEth amount. False to withdraw based on amount of Eth
    function withdrawEth(bool redeemType, uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEtherContract = assetToCAsset[
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ];

        // Create a reference to the corresponding cToken contract, like cDAI
        ICEther cToken = ICEther(cEtherContract);

        // redeemType == true >> withdraw based on amount of cErc20
        if (redeemType == true) {
            RedeemLocalVars memory vars;

            vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

            vars.redeemTokens = amountToWithdraw;

            (vars.mathErr, vars.redeemAmount) = mulScalarTruncate(
                Exp({mantissa: vars.exchangeRateMantissa}),
                amountToWithdraw
            );
            if (vars.mathErr != MathError.NO_ERROR) {
                return
                    failOpaque(
                        Error.MATH_ERROR,
                        FailureInfo.REDEEM_EXCHANGE_TOKENS_CALCULATION_FAILED,
                        uint256(vars.mathErr)
                    );
            }

            // require msg.sender has sufficient available balance of cEth
            require(
                (cAssetBalances[cEtherContract][msg.sender] -
                    utilizedCAssetBalances[cEtherContract][msg.sender]) >=
                    vars.redeemTokens,
                "Must have an available balance greater than or equal to amountToWithdraw"
            );

            cAssetBalances[cEtherContract][msg.sender] -= vars.redeemTokens;

            // Retrieve your asset based on an amountToWithdraw of the asset
            require(
                cToken.redeemUnderlying(vars.redeemAmount) == 0,
                "cToken.redeemUnderlying() failed"
            );

            // Repay eth to depositor
            (bool success, ) = (msg.sender).call{value: vars.redeemAmount}("");
            require(success, "Send eth to depositor failed");

            // redeemType == false >> withdraw based on amount of underlying
        } else {
            RedeemLocalVars memory vars;

            vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

            (vars.mathErr, vars.redeemTokens) = divScalarByExpTruncate(
                amountToWithdraw,
                Exp({mantissa: vars.exchangeRateMantissa})
            );
            if (vars.mathErr != MathError.NO_ERROR) {
                return
                    failOpaque(
                        Error.MATH_ERROR,
                        FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                        uint256(vars.mathErr)
                    );
            }

            vars.redeemAmount = amountToWithdraw;

            // require msg.sender has sufficient available balance of cEth
            require(
                (cAssetBalances[cEtherContract][msg.sender] -
                    utilizedCAssetBalances[cEtherContract][msg.sender]) >=
                    vars.redeemTokens,
                "Must have an available balance greater than or equal to amountToWithdraw"
            );

            cAssetBalances[cEtherContract][msg.sender] -= vars.redeemTokens;

            // Retrieve your asset based on an amountToWithdraw of the asset
            require(
                cToken.redeemUnderlying(vars.redeemAmount) == 0,
                "cToken.redeemUnderlying() failed"
            );

            // Repay eth to depositor
            (bool success, ) = (msg.sender).call{value: vars.redeemAmount}("");
            require(success, "Send eth to depositor failed");
        }

        emit EthWithdrawn(msg.sender, redeemType, amountToWithdraw);

        return 0;
    }

    function withdrawCEth(uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEtherContract = assetToCAsset[
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ];

        // Create a reference to the corresponding cToken contract, like cDAI
        ICEther cToken = ICEther(cEtherContract);

        // require msg.sender has sufficient available balance of cEth
        require(
            (cAssetBalances[cEtherContract][msg.sender] -
                utilizedCAssetBalances[cEtherContract][msg.sender]) >=
                amountToWithdraw,
            "Must have an available balance greater than or equal to amountToWithdraw"
        );

        // updating the depositors cErc20 balance
        cAssetBalances[cEtherContract][msg.sender] -= amountToWithdraw;

        // transfer cErc20 tokens to depositor
        require(
            cToken.transfer(msg.sender, amountToWithdraw) == true,
            "cToken.transfer failed. Have you approved the correct amount of Tokens"
        );

        emit CEthWithdrawn(msg.sender, amountToWithdraw);

        return amountToWithdraw;
    }
}
