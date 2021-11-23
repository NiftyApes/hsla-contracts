pragma solidity ^0.8.2;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./ErrorReporter.sol";
import "./Exponential.sol";
// import "./InterestRateModel.sol";

interface Erc20 {
    function approve(address, uint256) external returns (bool);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(address, address, uint256) external returns (bool);
}


interface CErc20 {
    function mint(uint256) external returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function supplyRatePerBlock() external returns (uint256);

    function redeem(uint) external returns (uint);

    function redeemUnderlying(uint) external returns (uint);

    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(address, address, uint) external returns (bool);
}


interface CEth {
    function mint() external payable;

    function exchangeRateCurrent() external returns (uint256);

    function supplyRatePerBlock() external returns (uint256);

    function redeem(uint) external returns (uint);

    function redeemUnderlying(uint) external returns (uint);

    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(address, address, uint) external returns (bool);
}

contract LiquidityProviders is Exponential, TokenErrorReporter {
    // Solidity 0.8.x provides safe math, but uses an invalid opcode error which comsumes all gas. SafeMath uses revert which returns all gas. 
    using SafeMath for uint256;


    // ---------- STRUCTS --------------- //

     struct MintLocalVars {
        Error err;
        MathError mathErr;
        uint exchangeRateMantissa;
        uint mintTokens;
        uint totalSupplyNew;
        uint accountTokensNew;
        uint mintAmount;
    }
    
    struct RedeemLocalVars {
        Error err;
        MathError mathErr;
        uint exchangeRateMantissa;
        uint redeemTokens;
        uint redeemAmount;
        uint totalSupplyNew;
        uint accountTokensNew;
    }


    // ---------- STATE VARIABLES --------------- //

    // Mapping of cErc20Balance to cErc20Address to depositor address
    mapping(address => mapping(address => uint256)) public cErc20Balances;

    // Mapping of ethBalance to depositorAddress
    mapping(address => uint256) public cEthBalances;

    // ---------- EVENTS --------------- //

    event MyLog(string, uint256);

    event EthDeposited( address _depositor, bool _depositType, uint256 _amount );

    event EthWithdrawn( address _depositor, bool _redeemType, uint256 _amount );

    // ---------- MODIFIERS --------------- //

    // ---------- FUNCTIONS -------------- //


    // returns number of cErc20 tokens added to balance
    function supplyErc20(
        address _erc20Contract,
        address _cErc20Contract,
        bool depositType,
        uint256 _numTokensToSupply
    ) public returns (uint) {

        console.log("_erc20Contract", _erc20Contract);
        console.log("_cErc20Contract", _cErc20Contract);
        console.log("depositType", depositType);
        console.log("_numTokensToSupply", _numTokensToSupply);

        // Create a reference to the underlying asset contract, like DAI.
        Erc20 underlying = Erc20(_erc20Contract);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(_cErc20Contract);

        uint256 supplyResult;

        // depositType == true >> add cErc20 to balance
        if (depositType == true) {
             // transferFrom ERC20 from depositors address
            cToken.transferFrom(msg.sender, address(this), _numTokensToSupply);

            // updating the depositors cErc20 balance
            cErc20Balances[_cErc20Contract][msg.sender] = cErc20Balances[_cErc20Contract][msg.sender] += _numTokensToSupply;

            supplyResult = _numTokensToSupply;

        // depositType == false >> mint cErc20 and add to balance
        } else {

            // transferFrom ERC20 from depositors address
            bool tfResult = underlying.transferFrom(msg.sender, address(this), _numTokensToSupply);

            console.log("tfResult", tfResult);

            // Approve transfer on the ERC20 contract from LiquidityProviders contract
            bool approveResult = underlying.approve(_cErc20Contract, _numTokensToSupply);

            console.log("approveResult", approveResult);

            // calculate expectedAmountToBeMinted
            MintLocalVars memory vars;

            vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

            vars.mintAmount = _numTokensToSupply;

            (vars.mathErr, vars.mintTokens) = divScalarByExpTruncate(vars.mintAmount, Exp({mantissa: vars.exchangeRateMantissa}));

            console.log("vars.mintTokens", vars.mintTokens);

            // Mint cTokens
            uint mintResult = cToken.mint(_numTokensToSupply);

            // updating the depositors cErc20 balance
            cErc20Balances[_cErc20Contract][msg.sender] = cErc20Balances[_cErc20Contract][msg.sender] += vars.mintTokens;

            console.log("cErc20Balances[_cErc20Contract][msg.sender] 1", cErc20Balances[_cErc20Contract][msg.sender]);

            supplyResult = mintResult;
        }

        return supplyResult;
    }

    function withdrawErc20(
        address _erc20Contract,
        address _cErc20Contract,
        bool redeemType,
        uint256 _amountToWithdraw
    ) 
        public 
        returns (bool) {

        // add nonReentrant modifier

        // require msg.sender has sufficient balance of cErc20

        // Create a reference to the underlying asset contract, like DAI.
        Erc20 underlying = Erc20(_erc20Contract);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(_cErc20Contract);

        // `amount` is scaled up, see decimal table here:
        // https://compound.finance/docs#protocol-math

        uint256 redeemResult;

        // redeemType == true >> subtract from balance and transfer cErc20 to msg.sender
        if (redeemType == true) {

            console.log("cErc20Balances[_cErc20Contract][msg.sender] 1", cErc20Balances[_cErc20Contract][msg.sender]);

            // updating the depositors cErc20 balance
            cErc20Balances[_cErc20Contract][msg.sender] = cErc20Balances[_cErc20Contract][msg.sender] -= _amountToWithdraw;

            console.log("cErc20Balances[_cErc20Contract][msg.sender] 2", cErc20Balances[_cErc20Contract][msg.sender]);


            // Retrieve your asset based on a cToken amount
            redeemResult = cToken.redeem(_amountToWithdraw);

            cToken.transfer(msg.sender, _amountToWithdraw);
        
        // redeemType == false >> subtract from balance and redeem erc20 and transfer to msg.sender
        } else {
            // need to convert underlying amount to ctoken in order to update cErc20Balance
            // need to calculate number of cErc20 tokens in _amountToWithdraw

            //  provided a erc20 amount, need to calculate how many cErc20 
           
            RedeemLocalVars memory vars;
            
            // MathError.NO_ERROR is an enum value in CarefulMath
            // exchangeRateStoredInternal is a function in cToken
            // failOpaque is a function in ErrorReporter
            // FailureInfo is an enum in ErrorReporter
             /* exchangeRate = invoke Exchange Rate Stored() */
            // (vars.mathErr, vars.exchangeRateMantissa) = exchangeRateStoredInternal();
            // if (vars.mathErr != MathError.NO_ERROR) {
            //     return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_EXCHANGE_RATE_READ_FAILED, uint(vars.mathErr));
            // }

            vars.exchangeRateMantissa = cToken.exchangeRateCurrent();

            vars.redeemTokens = _amountToWithdraw;

            // mulScalarTruncate is a function in exponential.sol
            // Exp is a struct in ExponentialNoError
            (vars.mathErr, vars.redeemAmount) = mulScalarTruncate(Exp({mantissa: vars.exchangeRateMantissa}), _amountToWithdraw);
            // if (vars.mathErr != MathError.NO_ERROR) {
            //     return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_EXCHANGE_TOKENS_CALCULATION_FAILED, uint(vars.mathErr));
            // }
            
            cErc20Balances[_cErc20Contract][msg.sender] = cErc20Balances[_cErc20Contract][msg.sender] -= vars.redeemAmount;

            // Retrieve your asset based on an _amountToWithdraw of the asset
            redeemResult = cToken.redeemUnderlying(vars.redeemAmount);

            underlying.transfer(msg.sender, vars.redeemAmount);
        }

        // Error codes are listed here:
        // https://compound.finance/docs/ctokens#error-codes
        emit MyLog("If this is not 0, there was an error", redeemResult);

        return true;
    }

    // ETH is difficult to store a ctoken balance for due to exponential math and native function not returning cToken quantity minted. ERC20 Tokens may be much easier.

    // depositType == true for CEth, false for Eth
    function depositETH(
        uint256 amount,
        bool depositType,
        address payable _cEtherContract
        ) 
        public
        payable
        returns (bool)
    {


        // Compound mainnet CEth contract address is 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5
        require(
            _cEtherContract == 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5,
            "cEtherContract must be Compound cEtherContract address 0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5"
        );

        // Create a reference to the corresponding cToken contract
        CEth cToken = CEth(_cEtherContract);
        // Could simply enforce a single contract to interact with, then dont need require statement to check address
        // CEth cToken = CEth(0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5);

        // true = deposit CEth
        if (depositType == true) {

            // transfer CEth from user to contract

            cEthBalances[msg.sender] += amount;

            console.log("msg.sender CEthBalance 1", cEthBalances[msg.sender]);

        
        // else = deposit Eth
        } else {

            // Amount of current exchange rate from cToken to underlying
            // uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();
            
            // console.log("exchangeRateMantissa", exchangeRateMantissa);

            // uint256 oneCtokenInUnderlying = SafeMath.div(exchangeRateMantissa, 1**28);

            // console.log("oneCtokenInUnderlying", oneCtokenInUnderlying);

            // // check that the cEthBalance is sufficient to withdraw requested amount of Eth

            // uint256 amountInCEth = msg.value / oneCtokenInUnderlying;

            // console.log("amountInCEth", amountInCEth);

            // cEthBalances[msg.sender] += amountInCEth;

            // console.log("msg.sender CEthBalance 2", cEthBalances[msg.sender]);

            // // Should this reference the CEth instanc above? 
            // // mint CEth tokens to this contract address
            // cToken.mint{ value: msg.value, gas: 250000 }();

        }

        uint256 CEthBalance = cToken.balanceOf(address(this));

        emit EthDeposited(msg.sender, depositType, amount);

        console.log("Contract CEthBalance 3", CEthBalance);

        return true;
    }

    // `amount` is scaled up by 1e18 to avoid decimals
    function withdrawETH(
        uint256 amount,
        bool redeemType,
        address _cEtherContract
    ) public returns (bool) {

        

        // Create a reference to the corresponding cToken contract
        CEth cToken = CEth(_cEtherContract);

        // uint256 currentCEthBalance = cEthBalances[msg.sender];

        // cEthBalances[msg.sender] = currentCEthBalance - amount;

       uint256 redeemResult;

        if (redeemType == true) {
            // require msg.sender has sufficient balance of CEth in contract
            require(
                cEthBalances[msg.sender] >= amount,
                "Withdrawl amount must but less than or equal to depositor's balance"
            );

            // Retrieve your asset based on a cToken amount
            redeemResult = cToken.redeem(amount);

            // Update address cEthBalance
            // Transfer cEth to depositer
        } else {
            // Amount of current exchange rate from cToken to underlying
            uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();

            // check that the cEthBalance is sufficient to withdraw requested amount of Eth

            uint256 balanceInEth = exchangeRateMantissa.mul(cEthBalances[msg.sender]);

            console.log("msg.sender balanceInEth", balanceInEth);

              // require msg.sender has sufficient balance of CEth in contract
            require(
                balanceInEth >= amount,
                "Withdrawl amount must but less than or equal to depositor's balance"
            );

            console.log("msg.sender old CEthBalance", cEthBalances[msg.sender]);
            // Update address cEthBalance
            cEthBalances[msg.sender] -= (exchangeRateMantissa * amount);
            console.log("msg.sender new CEthBalance", cEthBalances[msg.sender]);
            
            // Retrieve your asset based on an amount of the asset
            redeemResult = cToken.redeemUnderlying(amount);

            // Repay eth to depositor
            (bool success, ) = (msg.sender).call{value: amount}("");
            require(success, "Send eth to depositor failed");
        }

        // Error codes are listed here:
        // https://compound.finance/docs/ctokens#error-codes
        emit MyLog("If this is not 0, there was an error", redeemResult);


        uint256 CEthBalance = cToken.balanceOf(address(this));

        emit EthWithdrawn(msg.sender, redeemType, amount);

        console.log("Contract CEthBalance 2", CEthBalance);


        return true;
    }

    function withdrawCOMP() public {}

    // This is needed to receive ETH when calling `redeemCEth`
    receive() external payable {}

}