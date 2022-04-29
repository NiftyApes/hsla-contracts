// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

pragma solidity ^0.8.13;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/niftyapes/INiftyApes.sol";
import "./interfaces/chainlink/IChainlinkOracle.sol";

contract Strategy is BaseStrategy, Ownable {
    using SafeERC20 for IERC20;
    using Address for address;

    INiftyApes public constant NIFTYAPES = INiftyApes(address(0));
    address public constant BAYC = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
    address public constant XBAYC = 0xEA47B64e1BFCCb773A0420247C0aa0a3C1D2E5C5;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant SUSHILP = 0xD829dE54877e0b66A2c3890b702fa5Df2245203E;
    address public constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant DAI = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    IChainlinkOracle public constant ETHORACLE = IChainlinkOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    IChainlinkOracle public constant GASORACLE = IChainlinkOracle(0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C);
    uint256 public constant PRECISION = 1e18;

    uint256 public lastFloorPrice;
    uint256 public lastOfferDate;
    uint32 public expirationWindow = 7 days;

    uint256 public allowedDelta = 1e16; // 1% based on PRECISION
    uint256 public collatRatio = 25 * 1e16; // 25%
    uint96 public interestRatePerSecond = 1; // in basis points

    // strategist should update the profit potential in order to keep the strategy up to date with the market
    uint256 public thirtyDayProfitPotential;
    uint256 public offersInLastMonth;
    uint256 public removesInLastMonth;
    uint256 public removeOfferGas = 8374;
    uint256 public createOfferGas = 131110;

    ILendingStructs.Offer public offer;
    bytes32 public offerHash;

    // https://github.com/yearn/yearn-vaults/blob/main/contracts/BaseStrategy.sol
    constructor(
        address _vault,
        ILendingStructs.Offer memory _offer
    ) BaseStrategy(_vault) {
        // You can set these parameters on deployment to whatever you want
        // maxReportDelay = 6300;  // The maximum number of seconds between harvest calls
        // profitFactor = 100; // The minimum multiple that `callCost` must be above the credit/profit to be "justifiable";
        // debtThreshold = 0; // Use this to adjust the threshold at which running a debt causes harvest trigger
        want = IERC20(DAI);
        offer.creator = address(this);
        _setOffer(_offer);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return "StrategyNiftyApesBAYC";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        // TODO: Build a more accurate estimate using the value of all positions in terms of `want`
        return want.balanceOf(address(this)) + calculateDaiBalance();
    }

    // TODO: how to calculate profit even if loans are made out - cdai balance of contract would be
    // less than what it started with as long as a loan is out and profit earned is less than the outstanding
    // loan value
    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // TODO: Do stuff here to free up any returns back into `want`
        // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
        // NOTE: Should try to free up at least `_debtOutstanding` of underlying position
        uint256 oldWantBalance = want.balanceOf(address(this));

        // see how much cDAI nifty apes has vs what the debt of cdai is worth
        // TODO: implement this function
        // uint256 debtInCDai = NIFTYAPES.roughAssetAmountToCAssetAmount(
        //     address(want), _debtOutstanding
        // );
        uint256 debtInCDai = 0;
        uint256 cDaiBalance = NIFTYAPES.getCAssetBalance(address(this), CDAI);

        // withdraw excess cDai
        uint256 debt = vault.strategies(address(this)).totalDebt;

        if (cDaiBalance > debtInCDai) {
            NIFTYAPES.withdrawCErc20(CDAI, cDaiBalance - debtInCDai);
            _profit = want.balanceOf(address(this)) - oldWantBalance;
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // NOTE: ignore _debtOutstanding
        _debtOutstanding;

        // Deposit any additional want token into nifty apes
        uint256 daiToDeposit = want.balanceOf(address(this));
        if (daiToDeposit > 0) NIFTYAPES.supplyErc20(address(DAI), daiToDeposit);

        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)
        uint256 floorPrice = calculateFloorPrice();
        uint256 delta = calculateDelta(lastFloorPrice, floorPrice);
        if (canOffer(delta)) {
            removeOffer();
            createOffer(floorPrice);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // TODO: Do stuff here to free up to `_amountNeeded` from all positions back into `want`
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        uint256 totalAssets = want.balanceOf(address(this));

        if (_amountNeeded > totalAssets) {
            // Check amount of balance withdrawable
            // Withdraw only amount needed if there's enough
            /// Otherwise remove all
            uint256 wantToWithdraw = calculateDaiBalance();
            if (totalAssets + wantToWithdraw > _amountNeeded) wantToWithdraw = _amountNeeded - totalAssets;
            NIFTYAPES.withdrawErc20(address(want), wantToWithdraw);
            // refresh total assets from withdrawal
            totalAssets = want.balanceOf(address(this));
        }

        // NOTE: this logic is left as-is from template strategy
        if (_amountNeeded > totalAssets) {
            _liquidatedAmount = totalAssets;
            unchecked {
                _loss = _amountNeeded - totalAssets;
            }
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    /**
     * Liquidate everything and returns the amount that got freed.
     * This function is used during emergency exit instead of `prepareReturn()` to
     * liquidate all of the Strategy's positions back to the Vault.
     */
    function liquidateAllPositions() internal override returns (uint256 wantBalance) {

        NIFTYAPES.withdrawErc20(address(want), calculateDaiBalance());
        wantBalance = want.balanceOf(address(this));

        removeOffer();
        // NOTE: needs to be re-called when outstanding loans expire
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
        liquidateAllPositions();
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](3);
        protected[0] = XBAYC;
        protected[1] = WETH;
        protected[2] = SUSHILP;
        return protected;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // Rough - get price of ETH and convert to wei
        _amtInWei = uint256(ETHORACLE.latestAnswer()) * 1e10;
    }


    // ******************************************************************************
    //                                  NEW METHODS
    // ******************************************************************************

    // TODO: create a seize / seize and sell

    function removeOffer() private {
        // Remove the outstanding offer if it's still live, as we are about
        // to make a new offer
        if (offer.expiration > block.timestamp && offer.expiration != 0) {
            NIFTYAPES.removeOffer(BAYC, 0, offerHash, true);
            // Reset expiriation so if remove offer is called again we don't 
        }
    }

    function createOffer(
        uint256 floorPrice
    ) private {
        offer.expiration = uint32(block.timestamp) + expirationWindow;
        offer.amount = uint128(floorPrice * collatRatio / PRECISION);
        
        NIFTYAPES.createOffer(offer); // TODO: have this return offer hash
        offerHash = "";

        lastFloorPrice = floorPrice;
        lastOfferDate = block.timestamp;
    }

    // NOTE: does not need to have access control as this contract will receive
    function seizeAsset(uint256 nftId) external {
        NIFTYAPES.seizeAsset(BAYC, nftId);
    }
    function withdrawSeizedAsset(address to, uint256 nftId) external onlyOwner {
        IERC721(BAYC).transferFrom(address(this), to, nftId);
    }

    function setExpirationWindow(uint32 _expirationWindow) external onlyOwner {
        require(_expirationWindow != expirationWindow, "Same window");
        require(_expirationWindow > 1 days, "Too short of a window");
        expirationWindow = _expirationWindow;
    }


    function setOffer(ILendingStructs.Offer memory _offer) external onlyOwner {
        removeOffer();
        _setOffer(_offer);
    }

    function _setOffer(ILendingStructs.Offer memory _offer) private {
        offer.duration = _offer.duration;
        offer.fixedTerms = _offer.fixedTerms;
        offer.floorTerm = _offer.floorTerm;
        offer.lenderOffer = _offer.lenderOffer;
        offer.nftContractAddress = _offer.nftContractAddress;
        offer.asset = _offer.asset;
        offer.interestRatePerSecond = _offer.interestRatePerSecond;
    }


    // thirtyDayProfitPotential should be calculated by finding the number of new loans in the last 30 days
    // And multiplying the interestRatePerSecond by the duration of the loan
    function setThirtyDayProfitPotential(uint256 amount) public onlyAuthorized {
        thirtyDayProfitPotential = amount;
    }

    function setThirtyDayStrategyOffers(uint256 createAmount, uint256 removeAmount) public onlyAuthorized {
        offersInLastMonth = createAmount;
        removesInLastMonth = removeAmount;
    }

    function isProfitable() public view returns (bool) {
        return calculateProfitability() > 0;
    }

    //  this could instead be supplied as setThirtyDayProfitPotential
    function calculateProfitability() public view returns (int256) {
        return int256(thirtyDayProfitPotential) - int256(calculateGasPerMonth());

    }

    function calculateGasPerMonth() public view returns (uint256) {
        return offersInLastMonth * createOfferGas + removesInLastMonth * removeOfferGas;
    }

    function calculateCostOfGasPerMonth() public view returns (uint256) {
        uint256 gasPrice = uint256(GASORACLE.latestAnswer()) / 1e9; // returns gas in gwei
        uint256 ethPrice = uint256(ETHORACLE.latestAnswer()) / 1e8; // returns eth price in $
        return calculateGasPerMonth() * gasPrice * ethPrice / 1e9; // Divide by 1e9 as there's 1e9 gwei of gas in an ETH
    }


    // NOTE: this isn't exactly the spot price NFTx offers but it's "good enough"
    function calculateFloorPrice() public view returns (uint256 floorPrice) {
        // Fetch current pool of sushi LP
        // balance of xBAYC
        uint256 wethBalance = IERC20(WETH).balanceOf(SUSHILP);
        uint256 xbaycBalance = IERC20(XBAYC).balanceOf(SUSHILP);
        uint256 floorInEth = PRECISION * wethBalance / xbaycBalance;
        uint256 ethPrice = uint256(ETHORACLE.latestAnswer()) / 1e8; // to get price in dollars
        floorPrice = floorInEth * ethPrice;
    }

    function calculateDelta(uint256 oldPrice, uint256 newPrice) private pure returns (uint256) {
        return newPrice > oldPrice 
            ? PRECISION * (newPrice - oldPrice) / oldPrice
            : PRECISION * (oldPrice - newPrice) / oldPrice;
    }

    // Make offer if
    //  - price delta is met
    //  - last offer expired, in which we'd need to renew our old offer
    // Make offer if differential met OR last offer is expired
    function canOffer(uint256 delta) public view returns (bool) {
        return delta > allowedDelta || block.timestamp > offer.expiration;
    }


    // Take the CDAI balance of this contract within NIFTY and convert to DAI
    function calculateDaiBalance() public view returns (uint256 daiBalance) {
        uint256 cdaiBalance = NIFTYAPES.getCAssetBalance(address(this), CDAI);
        // assume current implementation will add this func- TODO
        // daiBalance = NIFTYAPES.cAssetAmountToAssetAmount(CDAI, cdaiBalance);
        daiBalance = 0;
    }

    /*
    Assuptions from NIFTYAPES
    - NIFTYAPES contract implements `cAssetAmountToAssetAmount()`
    - NIFTYAPES contract implements `roughAssetAmountToCAssetAmount()` (as seen in this PR)
    - NIFTYAPES contract adds a return value to `createOffer()`
    - Constant `NIFTYAPES` is set in this contract



    Stragegies used for reference
    https://yearn.watch/network/ethereum/vault/0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE/strategy/0xbeddd783be73805febda2c40a2bf3881f04fd7cc
    https://yearn.watch/network/ethereum/vault/0xdA816459F1AB5631232FE5e97a05BBBb94970c95/strategy/0xa6d1c610b3000f143c18c75d84baa0ec22681185
    */

}
