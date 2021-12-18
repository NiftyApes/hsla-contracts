pragma solidity ^0.8.2;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ErrorReporter.sol";
import "./Exponential.sol";

interface Erc20 {
    function approve(address, uint256) external returns (bool);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);
}

interface CErc20 {
    function mint(uint256) external returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function supplyRatePerBlock() external returns (uint256);

    function redeem(uint256) external returns (uint256);

    function redeemUnderlying(uint256) external returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);
}

interface CEth {
    function mint() external payable;

    function exchangeRateCurrent() external returns (uint256);

    function supplyRatePerBlock() external returns (uint256);

    function redeem(uint256) external returns (uint256);

    function redeemUnderlying(uint256) external returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);
}

// need to implement Proxy and Intitializable contracts

contract LiquidityProviders is
    Exponential,
    TokenErrorReporter,
    Ownable,
    Pausable,
    ReentrancyGuard
{
    // Solidity 0.8.x provides safe math, but uses an invalid opcode error which comsumes all gas. SafeMath uses revert which returns all gas.
    using SafeMath for uint256;

    // ---------- STRUCTS --------------- //

    struct MintLocalVars {
        Error err;
        MathError mathErr;
        uint256 exchangeRateMantissa;
        uint256 mintTokens;
        uint256 totalSupplyNew;
        uint256 accountTokensNew;
        uint256 mintAmount;
    }

    struct RedeemLocalVars {
        Error err;
        MathError mathErr;
        uint256 exchangeRateMantissa;
        uint256 redeemTokens;
        uint256 redeemAmount;
        uint256 totalSupplyNew;
        uint256 accountTokensNew;
    }

    // ---------- STATE VARIABLES --------------- //

    // Mapping of assetAddress to cAssetAddress
    // controls assets available for deposit on NiftyApes
    mapping(address => address) public assetToCAsset;

    // Mapping of cErc20Balance to cErc20Address to depositor address
    mapping(address => mapping(address => uint256)) public cErc20Balances;

    // Mapping of cErc20Balance to cErc20Address to depositor address
    mapping(address => mapping(address => uint256))
        public utilizedCErc20Balances;

    /**
     * @notice Mapping of allCAssetsEntered to depositorAddress
     */
    mapping(address => address[]) public accountAssets;
    // needed to calulate the lenders total value deposited on the platform

    // ---------- EVENTS --------------- //

    event MyLog(string, uint256);

    event EthSupplied(address _depositor, uint256 _amount);

    event CEthSupplied(address _depositor, uint256 _amount);

    event EthWithdrawn(address _depositor, bool _redeemType, uint256 _amount);

    // ---------- MODIFIERS --------------- //

    // ---------- FUNCTIONS -------------- //

    function getAssetsIn(address account)
        external
        view
        returns (address[] memory)
    {
        address[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    function setCAssetAddress(address asset, address cAsset)
        external
        onlyOwner
    {
       assetToCAsset[asset] = cAsset;
    }

    // returns number of cErc20 tokens added to balance
    function supplyErc20(
        address _erc20Contract,
        uint256 _numTokensToSupply
    ) public returns (uint256) {

        require(
            assetToCAsset[_erc20Contract] !=
                0x0000000000000000000000000000000000000000,
            "Asset not whitelisted on NiftyApes"
        );

        // Create a reference to the underlying asset contract, like DAI.
        Erc20 underlying = Erc20(_erc20Contract);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(assetToCAsset[_erc20Contract]);

        // should have require statement to ensure tranfer is successful before proceeding
        // transferFrom ERC20 from depositors address
        underlying.transferFrom(msg.sender, address(this), _numTokensToSupply);

        // need to provide
        // Approve transfer on the ERC20 contract from LiquidityProviders contract
        underlying.approve(assetToCAsset[_erc20Contract], _numTokensToSupply);

        // calculate expectedAmountToBeMinted
        MintLocalVars memory vars;

        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        vars.mintAmount = _numTokensToSupply;

        (vars.mathErr, vars.mintTokens) = divScalarByExpTruncate(
            vars.mintAmount,
            Exp({mantissa: vars.exchangeRateMantissa})
        );

        // should have require statement to ensure mint is successful before proceeding
        // Mint cTokens
        uint256 mintResult = cToken.mint(_numTokensToSupply);

        // updating the depositors cErc20 balance
        cErc20Balances[assetToCAsset[_erc20Contract]][msg.sender] += vars.mintTokens;

        return vars.mintTokens;
    }

    function supplyCErc20(address _cErc20Contract, uint256 _numTokensToSupply)
        public
        returns (uint256)
    {
        console.log("_cErc20Contract", _cErc20Contract);
        console.log("_numTokensToSupply", _numTokensToSupply);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(_cErc20Contract);

        // should have require statement to ensure tranfer is successful before updating the balance
        // transferFrom ERC20 from depositors address
        cToken.transferFrom(msg.sender, address(this), _numTokensToSupply);

        // updating the depositors cErc20 balance
        cErc20Balances[_cErc20Contract][msg.sender] += _numTokensToSupply;

        return _numTokensToSupply;
    }

    // currently implemented as "true" optino in withdrawErc20.
    function withdrawCErc20(
        address _erc20Contract,
        address _cErc20Contract,
        uint256 _amountToWithdraw
    ) public whenNotPaused nonReentrant returns (uint256) {
        // add nonReentrant modifier

        // Create a reference to the underlying asset contract, like DAI.
        Erc20 underlying = Erc20(_erc20Contract);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(_cErc20Contract);

        // require availble balance is sufficent
        // check total balance - utilized balance

        // require msg.sender has sufficient balance of cErc20
        require(
            cErc20Balances[_cErc20Contract][msg.sender] >= _amountToWithdraw,
            "Must have a balance greater than or equal to amountToWithdraw"
        );
        // updating the depositors cErc20 balance
        cErc20Balances[_cErc20Contract][msg.sender] = cErc20Balances[
            _cErc20Contract
        ][msg.sender] -= _amountToWithdraw;

        // should have require statement to ensure tranfer is successful before proceeding
        // transfer cErc20 tokens to depositor
        cToken.transfer(msg.sender, _amountToWithdraw);

        return _amountToWithdraw;
    }

    // True to withdraw based on cErc20 amount. False to withdraw based on amount of underlying erc20
    function withdrawErc20(
        address _erc20Contract,
        address _cErc20Contract,
        bool redeemType,
        uint256 _amountToWithdraw
    ) public whenNotPaused nonReentrant returns (uint256) {
        // add nonReentrant modifier

        // Create a reference to the underlying asset contract, like DAI.
        Erc20 underlying = Erc20(_erc20Contract);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(_cErc20Contract);

        // redeemType == true >> withdraw based on amount of cErc20
        if (redeemType == true) {
            RedeemLocalVars memory vars;

            vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

            vars.redeemTokens = _amountToWithdraw;

            (vars.mathErr, vars.redeemAmount) = mulScalarTruncate(
                Exp({mantissa: vars.exchangeRateMantissa}),
                _amountToWithdraw
            );
            if (vars.mathErr != MathError.NO_ERROR) {
                return
                    failOpaque(
                        Error.MATH_ERROR,
                        FailureInfo.REDEEM_EXCHANGE_TOKENS_CALCULATION_FAILED,
                        uint256(vars.mathErr)
                    );
            }

            // requre avail balance

            // require msg.sender has sufficient balance of cErc20
            require(
                cErc20Balances[_cErc20Contract][msg.sender] >=
                    vars.redeemTokens,
                "Must have a balance greater than or equal to redeemAmount"
            );

            cErc20Balances[_cErc20Contract][msg.sender] = cErc20Balances[
                _cErc20Contract
            ][msg.sender] -= vars.redeemTokens;

            // should have require statement to ensure redeem is successful before proceeding
            // Retrieve your asset based on an _amountToWithdraw of the asset
            cToken.redeemUnderlying(vars.redeemAmount);

            // should have require statement to ensure tranfer is successful before proceeding
            underlying.transfer(msg.sender, vars.redeemAmount);

            // redeemType == false >> withdraw based on amount of underlying
        } else {
            RedeemLocalVars memory vars;

            vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

            (vars.mathErr, vars.redeemTokens) = divScalarByExpTruncate(
                _amountToWithdraw,
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

            vars.redeemAmount = _amountToWithdraw;

            console.log(
                "cErc20Balances[_cErc20Contract][msg.sender]",
                cErc20Balances[_cErc20Contract][msg.sender]
            );
            console.log("vars.redeemAmount", vars.redeemAmount);
            console.log("vars.redeemTokens", vars.redeemTokens);

            // require msg.sender has sufficient balance of cErc20
            require(
                cErc20Balances[_cErc20Contract][msg.sender] >=
                    vars.redeemTokens,
                "Must have a balance greater than or equal to redeemAmount"
            );

            cErc20Balances[_cErc20Contract][msg.sender] = cErc20Balances[
                _cErc20Contract
            ][msg.sender] -= vars.redeemTokens;

            // should have require statement to ensure redeem is successful before proceeding
            // Retrieve your asset based on an _amountToWithdraw of the asset
            cToken.redeemUnderlying(vars.redeemAmount);

            // should have require statement to ensure tranfer is successful before proceeding
            underlying.transfer(msg.sender, vars.redeemAmount);
        }

        return 0;
    }

    function supplyEth(address payable _cEtherContract)
        public
        payable
        returns (uint256)
    {
        // Require CEth contract address is 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5
        require(
            _cEtherContract == 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5,
            "cEtherContract must be Compound cEtherContract address 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5"
        );

        // Create a reference to the corresponding cToken contract
        CEth cToken = CEth(_cEtherContract);
        // Could simply enforce a single contract to interact with, then dont need require statement to check address
        // CEth cToken = CEth(0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5);

        // calculate expectedAmountToBeMinted
        MintLocalVars memory vars;

        vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

        (vars.mathErr, vars.mintTokens) = divScalarByExpTruncate(
            msg.value,
            Exp({mantissa: vars.exchangeRateMantissa})
        );

        // should have require statement to ensure mint is successful before proceeding
        // // mint CEth tokens to this contract address
        cToken.mint{value: msg.value, gas: 250000}();

        // updating the depositors cErc20 balance
        cErc20Balances[_cEtherContract][msg.sender] = cErc20Balances[
            _cEtherContract
        ][msg.sender] += vars.mintTokens;

        uint256 CEthBalance = cToken.balanceOf(address(this));

        emit EthSupplied(msg.sender, msg.value);

        console.log("Contract CEthBalance 3", CEthBalance);
        console.log("Contract vars.mintTokens 3", vars.mintTokens);

        return vars.mintTokens;
    }

    function supplyCEth(
        address payable _cEtherContract,
        uint256 _numTokensToSupply
    ) public payable returns (uint256) {
        // Compound mainnet CEth contract address is 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5
        require(
            _cEtherContract == 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5,
            "cEtherContract must be Compound cEtherContract address 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5"
        );

        // Create a reference to the corresponding cToken contract
        CEth cToken = CEth(_cEtherContract);
        // Could simply enforce a single contract to interact with, then dont need require statement to check address
        // CEth cToken = CEth(0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5);

        // should have require statement to ensure tranfer is successful before updating the balance
        // transferFrom ERC20 from supplyers address
        cToken.transferFrom(msg.sender, address(this), _numTokensToSupply);

        cErc20Balances[_cEtherContract][msg.sender] += _numTokensToSupply;

        console.log(
            "msg.sender CEthBalance 1",
            cErc20Balances[_cEtherContract][msg.sender]
        );

        uint256 CEthBalance = cToken.balanceOf(address(this));

        emit CEthSupplied(msg.sender, _numTokensToSupply);

        console.log("Contract CEthBalance 3", CEthBalance);

        return _numTokensToSupply;
    }

    // currently implemented as "true" optino in withdrawErc20.
    function withdrawCEth(address _cEtherContract, uint256 _amountToWithdraw)
        public
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        console.log("_cEtherContract", _cEtherContract);
        console.log("_amountToWithdraw", _amountToWithdraw);

        // add nonReentrant modifier

        // Compound mainnet CEth contract address is 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5
        require(
            _cEtherContract == 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5,
            "cEtherContract must be Compound cEtherContract address 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5"
        );

        // Create a reference to the corresponding cToken contract, like cDAI
        CEth cToken = CEth(_cEtherContract);

        // require msg.sender has sufficient balance of cErc20
        require(
            cErc20Balances[_cEtherContract][msg.sender] >= _amountToWithdraw,
            "Must have a balance greater than or equal to amountToWithdraw"
        );
        // updating the depositors cErc20 balance
        cErc20Balances[_cEtherContract][msg.sender] = cErc20Balances[
            _cEtherContract
        ][msg.sender] -= _amountToWithdraw;

        // should have require statement to ensure tranfer is successful before proceeding
        // transfer cErc20 tokens to depositor
        cToken.transfer(msg.sender, _amountToWithdraw);

        return _amountToWithdraw;
    }

    // True to withdraw based on cEth amount. False to withdraw based on amount of Eth
    function withdrawEth(
        address _cEtherContract,
        bool redeemType,
        uint256 _amountToWithdraw
    ) public whenNotPaused nonReentrant returns (uint256) {
        // add nonReentrant modifier

        // Create a reference to the corresponding cToken contract, like cDAI
        CEth cToken = CEth(_cEtherContract);

        // redeemType == true >> withdraw based on amount of cErc20
        if (redeemType == true) {
            RedeemLocalVars memory vars;

            vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

            vars.redeemTokens = _amountToWithdraw;

            (vars.mathErr, vars.redeemAmount) = mulScalarTruncate(
                Exp({mantissa: vars.exchangeRateMantissa}),
                _amountToWithdraw
            );
            if (vars.mathErr != MathError.NO_ERROR) {
                return
                    failOpaque(
                        Error.MATH_ERROR,
                        FailureInfo.REDEEM_EXCHANGE_TOKENS_CALCULATION_FAILED,
                        uint256(vars.mathErr)
                    );
            }

            // require msg.sender has sufficient balance of cErc20
            require(
                cErc20Balances[_cEtherContract][msg.sender] >=
                    vars.redeemTokens,
                "Must have a balance greater than or equal to redeemAmount"
            );

            cErc20Balances[_cEtherContract][msg.sender] = cErc20Balances[
                _cEtherContract
            ][msg.sender] -= vars.redeemTokens;

            // should have require statement to ensure redeem is successful before proceeding
            // Retrieve your asset based on an _amountToWithdraw of the asset
            cToken.redeemUnderlying(vars.redeemAmount);

            // Repay eth to depositor
            (bool success, ) = (msg.sender).call{value: vars.redeemAmount}("");
            require(success, "Send eth to depositor failed");

            // redeemType == false >> withdraw based on amount of underlying
        } else {
            RedeemLocalVars memory vars;

            vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

            (vars.mathErr, vars.redeemTokens) = divScalarByExpTruncate(
                _amountToWithdraw,
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

            vars.redeemAmount = _amountToWithdraw;

            console.log(
                "cErc20Balances[_cEtherContract][msg.sender]",
                cErc20Balances[_cEtherContract][msg.sender]
            );
            console.log("vars.redeemAmount", vars.redeemAmount);
            console.log("vars.redeemTokens", vars.redeemTokens);

            // require msg.sender has sufficient balance of cErc20
            require(
                cErc20Balances[_cEtherContract][msg.sender] >=
                    vars.redeemTokens,
                "Must have a balance greater than or equal to redeemAmount"
            );

            cErc20Balances[_cEtherContract][msg.sender] = cErc20Balances[
                _cEtherContract
            ][msg.sender] -= vars.redeemTokens;

            // should have require statement to ensure redeem is successful before proceeding
            // Retrieve your asset based on an _amountToWithdraw of the asset
            cToken.redeemUnderlying(vars.redeemAmount);

            // Repay eth to depositor
            (bool success, ) = (msg.sender).call{value: vars.redeemAmount}("");
            require(success, "Send eth to depositor failed");
        }

        return 0;
    }

    // need to work out how to calculate the amount of comp accrued to each deposit. Might need a struct for each balance which tracks the amount of time elapsed for each segment of value.
    function withdrawCompEarned() public {}

    // need to query the COMP distribution rate at the time of deposit
    // the COMP distribution rate can only change per asset via a COMP DAO VOTE

    // the answer to this is in 'distributeSupplierComp' in comptrollerG7.sol
    // this may also provide a method to calculate interest accrued by lenders
    // checkout updateContributorRewards
    function calculateCompEarned() public {}

    function calculateLiquidityInterestEarned() public {}

    function calculateErc20WithdrawalFee(
        address _erc20Contract,
        address _cErc20Contract,
        bool redeemType,
        uint256 _amountToWithdraw
    ) public {}

    function calculateLoanDrawDownFee() public {}

    // This function will remain empty until NiftyApes reaches sufficient decentralization
    // function adminWithdrawal() public onlyOwner {}

    // if possible should implement function to reject any ETH or ERC20 that is directly sent to the contract

    // This is needed to receive ETH when calling `withdrawEth`
    receive() external payable {}
}
