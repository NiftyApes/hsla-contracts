# H-01: Value leaks due to fee-on-transfers on some ERC20 tokens is not being considered

## Vulnerability details
Some ERC20 tokens, such as USDT[contract code](https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7#code), allow for charging a fee any time transfer() or transferFrom() is called. If a contract does not allow for amounts to change after transfers, subsequent transfer operations based on the original amount will revert() due to the contract having an insufficient balance. 
And even if a token is currently not charging a fee, a future upgrade to the token may institute one.

## Impact
instance #1
Link: https://github.com/NiftyApes/contracts/blob/main/src/Liquidity.sol#L469-L478
```solidity
contracts/gateway/L1GraphTokenGateway.sol

469:        underlying.safeTransferFrom(from, address(this), amount);
478:        require(cToken.mint(amount) == 0, "00037");
            IERC20Upgradeable(asset).safeTransfer(to, amount);

```
instance #2
Link: https://github.com/NiftyApes/contracts/blob/main/src/Liquidity.sol#L454
```solidity
contracts/gateway/L1GraphTokenGateway.sol

454:            IERC20Upgradeable(asset).safeTransfer(to, amount);

```
The code assumes that the contract has received the full `amount` passed as input from the `safeTransferFrom` call rather than the actual amount transferred in the call. The calculation should take into account the fees charged as a part of the transfer so that the protocol does not leak value or doesn't revert if there is no extra balance already present in the contract.

For example, if fee-on-transfers leaks value at Liquidity.sol#L469, then Liquidity.sol#L478 will revert due to insufficient token balance in the contract (Or this will consume any extra balance already present in the contract before this call was made). Hence this function will always revert for all such ERC20 tokens.

## Tools Used
Manual Analysis

## Recommended Mitigation Steps
Measure the balance before and after the calls to safeTransferFrom(), and use the difference between the two as the amount, rather than the amount stated

***

## Gas Optimizations

### G-01: `x += y` costs more gas than `x = x + y` for state variables

Total instances of this issue: 20
Example instances:
```solidity
src/Lending.sol

332:            loanAuction.accumulatedLenderInterest += SafeCastUpgradeable.toUint128(
333:                interestThresholdDelta
334:            );

453:            protocolInterestAndPremium +=
454:                (uint256(loanAuction.amountDrawn) * termGriefingPremiumBps) /
455:                MAX_BPS;

490:                loanAuction.accumulatedLenderInterest += loanAuction.slashableLenderInterest;

502:            protocolInterestAndPremium += loanAuction.unpaidProtocolInterest;

```
 *** 


### G-02: No need to compare boolean expressions with boolean literals, directly use the expression
if (<x> == true) ==> if (<x>)
if (<x> == false) => if (!<x>)

Total instances of this issue: 1

```solidity
src/Lending.sol

879:        if (loanAuction.lenderRefi == true) {


```
 *** 


### G-03: Adding `payable` to functions which are only meant to be called by specific actors like `onlyOwner` will save gas cost
Marking functions payable removes additional checks for whether a payment was provided, hence reducing gas cost

Total instances of this issue: 30
Example instances:
```solidity
src/Lending.sol

111:    function updateProtocolInterestBps(uint16 newProtocolInterestBps) external onlyOwner {

118:    function updateOriginationPremiumLenderBps(uint16 newOriginationPremiumBps) external onlyOwner {

125:    function updateGasGriefingPremiumBps(uint16 newGasGriefingPremiumBps) external onlyOwner {
```
 *** 


### G-04: Using uints/ints smaller than 256 bits increases overhead
Gas usage becomes higher with uint/int smaller than 256 bits because EVM operates on 32 bytes and uses additional operations to reduce the size from 32 bytes to the target size.

Total instances of this issue: 32
Example instances:
```solidity
src/Lending.sol

63:    uint16 public protocolInterestBps;

66:    uint16 public originationPremiumBps;

69:    uint16 public gasGriefingPremiumBps;

72:    uint16 public termGriefingPremiumBps;

```
 *** 


### G-05: Using custom errors rather than revert()/require() strings will save deployment gas
Custom errors are available from solidity version 0.8.4.

Total instances of this issue: 67

```solidity
src/Lending.sol

249:        require(offer.asset != address(0), "00004");

256:        require(loanAuction.lastUpdatedTimestamp == 0, "00006");

260:        require(IERC721Upgradeable(offer.nftContractAddress).ownerOf(nftId) == borrower, "00018");

```
