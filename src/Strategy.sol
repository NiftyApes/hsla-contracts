// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";

import {AddressUpgradeable} from "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/niftyapes/INiftyApes.sol";
import "./interfaces/chainlink/IChainlinkOracle.sol";

contract Strategy is BaseStrategy, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    INiftyApes public constant NIFTYAPES = INiftyApes(address(0));
    address public constant BAYC = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
    address public constant XBAYC = 0xEA47B64e1BFCCb773A0420247C0aa0a3C1D2E5C5;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant SUSHILP = 0xD829dE54877e0b66A2c3890b702fa5Df2245203E;
    address public constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant DAI = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    IChainlinkOracle public constant ORACLE = IChainlinkOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    uint256 public constant PRECISION = 1e18;

    uint256 public lastFloorPrice;
    uint256 public lastOfferDate;
    uint256 public expirationWindow = 7 days;

    uint256 public allowedDelta = 1e16; // 1% based on PRECISION
    uint256 public collatRatio = 25 * 1e16; // 25%
    uint96 public interestRatePerSecond = 1; // in basis points

    uint256 public loansInLastMonth;
    uint256 public gasCostToCreateAndRemoveOffer;

    ILendingStructs.Offer public offer;
    bytes32 public offerHash;

    function setExpirationWindow(uint256 _expirationWindow) external {
        // if the new window is shorter - to remove active previous offers
        // if new window is longer - no need to remove as we can always assume the most recent
        // offer expiration is greater than an older offer
        // NOTE: ^ is irrelevant w/ only one offer
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
        offer.floorTerms = _offer.floorTerms;
        offer.lenderOffer = _offer.lenderOffer;
        offer.nftContractAddress = _offer.nftContractAddress;
        offer.asset = _offer.asset;
        offer.interestRatePerSecond = _offer.interestRatePerSecond;
    }

    // https://github.com/yearn/yearn-vaults/blob/main/contracts/BaseStrategy.sol
    constructor(
        address _vault,
        ILendingStructs.Offer memory _offer
    ) public BaseStrategy(_vault) {
        // You can set these parameters on deployment to whatever you want
        // maxReportDelay = 6300;  // The maximum number of seconds between harvest calls
        // profitFactor = 100; // The minimum multiple that `callCost` must be above the credit/profit to be "justifiable";
        // debtThreshold = 0; // Use this to adjust the threshold at which running a debt causes harvest trigger
        want = DAI;
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
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)

        uint128 floorPrice = calculateFloorPrice();
        uint256 delta = calculateDelta(lastFloorPrice, floorPrice);

        if (canOffer(delta)) {
            removeOffer();
            createOffer(delta, floorPrice);
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

        removeOffer();

        uint256 totalAssets = want.balanceOf(address(this));
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

        NIFTYAPES.withdrawERC20(want, calculateDaiBalance());
        wantBalance = want.balanceOf(address(this));

        removeOffer();

        // NOTE: needs to be re-called when outstanding loans expire
        

        // REQUIRED: Liquidate all positions and return the amount freed.
        // return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
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
        _amtInWei = ORACLE.latestAnswer() * 1e10;
    }


    // ******************************************************************************
    //                                  NEW METHODS
    // ******************************************************************************

    // TODO: offersInLastMonth, removesInLastMonth
    function calcMonthlyRevenue() external view returns (int256 revenue) {
        return calculateMonthlyProfit() - calculateGasPerMonth();
    }

    // TODO: loansInLastMonth
    function calculateMonthlyProfit() public view returns (uint256 monthlyProfit) {
        uint256 durationInDays = offer.duration / 1 days;
        uint256 profitPotential = offer.interestRatePerSecond * offer.duration * loansInLastMonth;
        monthlyProfit = profitPotential * durationInDays / 30;
    }

    function isProfitable() public returns (bool) {
        return calculateMonthlyProfit() > calculateGasPerMonth();
    }

    function calculateGasPerMonth() public returns (uint256) {
        uint256 offersInLastMonth = 0;
        uint256 removesInLastMonth = 0;
        return offersInLastMonth * gasCostCreateOffer() + removesInLastMonth * gasCostRemoveOffer();
    }

    function gasCostCreateOffer() public {
        // TODO: cost to create an offer
    }
    function gasCostRemoveOffer() public {
        // TODO: cost to remove an offer
    }


    function setLoansInLastMonth(uint256 amount) public onlyOwner {
        loansInLastMonth = amount;
    }

    // iterable mapping of structs
    // contract address => structHash => index => bool
    mapping(address => mapping(bytes32 => mapping(uint256 => bool))) public loans;

    struct OfferInfo {
        bytes32 offerHash;
        uint256 timestamp;
    }


    // NOTE: this isn't exactly the spot price NFTx offers but it's "good enough"
    function calculateFloorPrice() public view returns (uint256 floorPrice) {
        // Fetch current pool of sushi LP
        // balance of xBAYC
        uint256 wethBalance = IERC20Upgradeable(WETH).balanceOf(SUSHILP);
        uint256 xbaycBalance = IERC20Upgradeable(XBAYC).balanceOf(SUSHILP);
        uint256 floorInEth = PRECISION * wethBalance / xbaycBalance;
        uint256 ethPrice = ORACLE.latestAnswer() / 1e8; // to get price in dollars
        floorPrice = floorInEth * ethPrice;
    }

    function calculateDelta(uint256 oldPrice, uint256 newPrice) private returns (uint256) {
        return newPrice > oldPrice 
            ? PRECISION * (newPrice - oldPrice) / oldPrice
            : PRECISION * (oldPrice - newPrice) / oldPrice;
    }

    // Make offer if
    //  - price delta is met
    //  - last offer expired, in which we'd need to renew our old offer
    // Make offer if differential met OR last offer is expired
    function canOffer(uint256 delta) public returns (bool) {
        return delta > allowedDelta || block.timestamp > offer.expiration;
    }

    function removeOffer() private {
        // Remove the outstanding offer if it's still live, as we are about
        // to make a new offer
        if (offer.expiration > block.timestamp) {
            NIFTYAPES.doRemoveOffer(BAYC, 0, offerHash, true);
        }
    }

    function createOffer(
        uint256 delta,
        uint256 floorPrice
    ) private {
        offer.expiration = block.timestamp + expirationWindow;
        offer.amount = floorPrice * collatRatio / PRECISION;
        
        offerHash = NIFTYAPES.createOffer(offer); // TODO: have this return offer hash

        lastFloorPrice = floorPrice;
        lastOfferDate = block.timestamp;
    }

    // Take the CDAI balance of this contract within NIFTY and convert to DAI
    function calculateDaiBalance() public returns (uint256 daiBalance) {
        uint256 cdaiBalance = NIFTYAPES.getCAssetBalance(address(this), CDAI);
        // assume current implementation will add this func
        daiBalance = NIFTYAPES.cAssetAmountToAssetAmount(CDAI, cdaiBalance);
    }

    // TODO: to be CDAI?
    function freeAmount(uint256 daiAmount) internal returns (uint256 freedAmount) {
        // TODO: withdraw amount of balance to strategy
    }



    /*

    // TODO: flash loans - can they be executed in a block, or only in a tx?    
        - would a flash loan be able to impact the floor price when the keeper calls to refresh the offer?
        - (?) put a price movement tolerance to see if price is stable -> if price is much different
        - on this block vs. last - TWAP

    - A strategiest would configure:
        - Initial terms when strategy goes live
        - constructor arguments

    - Our "want" token to stack is DAI/USDC
    
    - can a keeper pass an argument into tend() - no
    - can a keeper make an external API call
    - can a k3pr handle an event
    */
}