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

    // constructor() {
    //     transferOwnership(0x5E3df1431aBf51a7729348C7B4bAe6AF80a85803);
    // }

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
    function supplyErc20(address erc20Contract, uint256 numTokensToSupply)
        public
        returns (uint256)
    {
        require(
            assetToCAsset[erc20Contract] !=
                0x0000000000000000000000000000000000000000,
            "Asset not whitelisted on NiftyApes"
        );

        // Create a reference to the underlying asset contract, like DAI.
        Erc20 underlying = Erc20(erc20Contract);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(assetToCAsset[erc20Contract]);

        // transferFrom ERC20 from depositors address
        require(
            underlying.transferFrom(
                msg.sender,
                address(this),
                numTokensToSupply
            ) == true,
            "underlying.transferFrom() failed"
        );

        // need to provide
        // Approve transfer on the ERC20 contract from LiquidityProviders contract
        underlying.approve(assetToCAsset[erc20Contract], numTokensToSupply);

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
        cErc20Balances[assetToCAsset[erc20Contract]][msg.sender] += vars
            .mintTokens;

        return vars.mintTokens;
    }

    function supplyCErc20(address erc20Contract, uint256 numTokensToSupply)
        public
        returns (uint256)
    {
        require(
            assetToCAsset[erc20Contract] !=
                0x0000000000000000000000000000000000000000,
            "Asset not whitelisted on NiftyApes"
        );

        address cErc20Contract = assetToCAsset[erc20Contract];

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(cErc20Contract);

        // transferFrom ERC20 from depositors address
        // cToken.transferFrom(msg.sender, address(this), numTokensToSupply);
        require(
            cToken.transferFrom(msg.sender, address(this), numTokensToSupply) ==
                true,
            "cToken transferFrom failed. Have you approved the correct amount of Tokens?"
        );

        // updating the depositors cErc20 balance
        cErc20Balances[cErc20Contract][msg.sender] += numTokensToSupply;

        return numTokensToSupply;
    }

    // True to withdraw based on cErc20 amount. False to withdraw based on amount of underlying erc20
    function withdrawErc20(
        address erc20Contract,
        bool redeemType,
        uint256 amountToWithdraw
    ) public whenNotPaused nonReentrant returns (uint256) {
        require(
            assetToCAsset[erc20Contract] !=
                0x0000000000000000000000000000000000000000,
            "Asset not whitelisted on NiftyApes"
        );

        address cErc20Contract = assetToCAsset[erc20Contract];

        // Create a reference to the underlying asset contract, like DAI.
        Erc20 underlying = Erc20(erc20Contract);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(cErc20Contract);

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
                (cErc20Balances[cErc20Contract][msg.sender] -
                    utilizedCErc20Balances[cErc20Contract][msg.sender]) >=
                    vars.redeemTokens,
                "Must have an available balance greater than or equal to amountToWithdraw"
            );

            cErc20Balances[cErc20Contract][msg.sender] -= vars.redeemTokens;

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
                (cErc20Balances[cErc20Contract][msg.sender] -
                    utilizedCErc20Balances[cErc20Contract][msg.sender]) >=
                    vars.redeemTokens,
                "Must have an available balance greater than or equal to amountToWithdraw"
            );

            cErc20Balances[cErc20Contract][msg.sender] -= vars.redeemTokens;

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

        return 0;
    }

    function withdrawCErc20(address erc20Contract, uint256 amountToWithdraw)
        public
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(
            assetToCAsset[erc20Contract] !=
                0x0000000000000000000000000000000000000000,
            "Asset not whitelisted on NiftyApes"
        );

        address cErc20Contract = assetToCAsset[erc20Contract];

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 cToken = CErc20(cErc20Contract);

        // require msg.sender has sufficient available balance of cErc20
        require(
            (cErc20Balances[cErc20Contract][msg.sender] -
                utilizedCErc20Balances[cErc20Contract][msg.sender]) >=
                amountToWithdraw,
            "Must have an available balance greater than or equal to amountToWithdraw"
        );
        // updating the depositors cErc20 balance
        cErc20Balances[cErc20Contract][msg.sender] -= amountToWithdraw;

        // transfer cErc20 tokens to depositor
        require(
            cToken.transfer(msg.sender, amountToWithdraw) == true,
            "cToken.transfer failed. Have you approved the correct amount of Tokens"
        );

        return amountToWithdraw;
    }

    function supplyEth() public payable returns (uint256) {
        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEtherContract = assetToCAsset[
            0x0000000000000000000000000000000000000000
        ];

        // Create a reference to the corresponding cToken contract
        CEth cToken = CEth(cEtherContract);

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
        cErc20Balances[cEtherContract][msg.sender] += vars.mintTokens;

        emit EthSupplied(msg.sender, msg.value);

        return vars.mintTokens;
    }

    function supplyCEth(uint256 numTokensToSupply)
        public
        returns (uint256)
    {
        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEtherContract = assetToCAsset[
            0x0000000000000000000000000000000000000000
        ];

        // Create a reference to the corresponding cToken contract
        CEth cToken = CEth(cEtherContract);

        // transferFrom ERC20 from supplyers address
        require(
            cToken.transferFrom(msg.sender, address(this), numTokensToSupply) ==
                true,
            "cToken.transferFrom failed"
        );

        cErc20Balances[cEtherContract][msg.sender] += numTokensToSupply;

        emit CEthSupplied(msg.sender, numTokensToSupply);

        return numTokensToSupply;
    }

    // True to withdraw based on cEth amount. False to withdraw based on amount of Eth
    function withdrawEth(bool redeemType, uint256 amountToWithdraw)
        public
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEtherContract = assetToCAsset[
            0x0000000000000000000000000000000000000000
        ];

        // Create a reference to the corresponding cToken contract, like cDAI
        CEth cToken = CEth(cEtherContract);

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
                (cErc20Balances[cEtherContract][msg.sender] -
                    utilizedCErc20Balances[cEtherContract][
                        msg.sender
                    ]) >= vars.redeemTokens,
                "Must have an available balance greater than or equal to amountToWithdraw"
            );

            cErc20Balances[cEtherContract][msg.sender] -= vars.redeemTokens;

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
                (cErc20Balances[cEtherContract][msg.sender] -
                    utilizedCErc20Balances[cEtherContract][
                        msg.sender
                    ]) >= vars.redeemTokens,
                "Must have an available balance greater than or equal to amountToWithdraw"
            );

            cErc20Balances[cEtherContract][msg.sender] -= vars.redeemTokens;

            // Retrieve your asset based on an amountToWithdraw of the asset
            require(
                cToken.redeemUnderlying(vars.redeemAmount) == 0,
                "cToken.redeemUnderlying() failed"
            );

            // Repay eth to depositor
            (bool success, ) = (msg.sender).call{value: vars.redeemAmount}("");
            require(success, "Send eth to depositor failed");
        }

        return 0;
    }

    function withdrawCEth(uint256 amountToWithdraw)
        public
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        // set cEth address
        // utilize reference to allow update of cEth address by compound in future versions
        address cEtherContract = assetToCAsset[
            0x0000000000000000000000000000000000000000
        ];

        // Create a reference to the corresponding cToken contract, like cDAI
        CEth cToken = CEth(cEtherContract);

        // require msg.sender has sufficient available balance of cEth
        require(
            (cErc20Balances[cEtherContract][msg.sender] -
                utilizedCErc20Balances[cEtherContract][
                    msg.sender
                ]) >= amountToWithdraw,
            "Must have an available balance greater than or equal to amountToWithdraw"
        );

        // updating the depositors cErc20 balance
        cErc20Balances[cEtherContract][msg.sender] -= amountToWithdraw;

        // transfer cErc20 tokens to depositor
        require(
            cToken.transfer(msg.sender, amountToWithdraw) == true,
            "cToken.transfer failed. Have you approved the correct amount of Tokens"
        );

        return amountToWithdraw;
    }

    // admin functions

    function adminTransferCErc20() public {}

    function adminRedeemAndTransferErc20() public {}

    // need to work out how to calculate the amount of comp accrued to each deposit. Might need a struct for each balance which tracks the amount of time elapsed for each segment of value.
    function withdrawCompEarned() public {}

    // need to query the COMP distribution rate at the time of deposit
    // the COMP distribution rate can only change per asset via a COMP DAO VOTE

    // the answer to this is in 'distributeSupplierComp' in comptrollerG7.sol
    // this may also provide a method to calculate interest accrued by lenders
    // checkout updateContributorRewards
    function calculateCompEarned() public {}

    function calculateLiquidityInterestEarned() public {}

    function calculateLoanDrawDownFee() public {}

    // if possible should implement function to reject any ETH or ERC20 that is directly sent to the contract

    // This is needed to receive ETH when calling `withdrawEth`
    receive() external payable {}
}
