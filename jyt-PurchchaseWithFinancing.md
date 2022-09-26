# Purchase With Financing

Author: [jyturley](https://github.com/jyturley)

## Requirements

- [x] New contract that extends to `Lending.sol`
- [x] New branch: `jyt-purchaseWithFinancing`
- [x] `purchaseWithFinancingOpenSea()` function
  - [x] Input: NiftyApes `Offer` info
  - [x] Input: OpenSea `BasicOrderParameters` struct
  - [x] Executes `fullfullBasicOrder()`
  - [x] Transacts in ETH
- [~] Optional: unit tests

## Provided Pseudo Code

```solidity
function purchaseWithFinancingOpenSea(
  Offer memory offer,
  BasicOrderParameters calldata order
) external payable {
  // check msg.sender’s balance
  // require offer.nftContract + offer.nftId == order.offerToken + order.offerIdentifier (NFT)
  // require offer.asset == order.considerationToken (ETH)
  // require msg.value == order.offerAmount - offer.amount (ETH amount)
  // update the lender’s balance in NiftyApes (subtract required amount)
  uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
    offer.asset,
    offer.amount
  );
  // redeemUnderlying asset from the lenders balance (convert required amount)
  ILiquidity(liquidityContractAddress).withdrawCBalance(
    lender,
    cAsset,
    cTokensBurned
  );

  // execute “fulfillBasicOrder” function
  // update loanAuction struct (this should be similar functionality to `_createLoan()`);
  emit LoanExecuted();
}

```

## Project Notes

- As of now this is a WIP solution.
- I believe I've implemented all the non-optional parts of the assignment.
- I am at 17/20hrs, and would like to check in with you guys if you would like me to continue working so that I can get the items listed below sorted out. With that said, I believe the issues I am experiencing are all related to the optional testing requirement for this assignment. This is why I can understand it will not be productive for you to pay me to continue.
- `purchaseWithFinancingOpenSea()` currently calls external functions only allowed by `Lending.sol`. Hence even though this function is in its own contract, it is designed to be implemented in `Lending.sol`.

## Testing

- Overall, I struggled with the testing aspect. This stems mostly from my lack of experience with the forge framework (I come from a Hardhat JS/TS testing background). The NiftyApes test suite is very tightly coupled with the lending contract, so incorporating my wholly new `PurchaseWithFinancing` contract proved difficult.
- I got around this by modifying `NiftyApesDeployment` test contract with the following code:

```solidity
liquidity.updateLendingContractAddress(address(purchaseWithFinancing));
sigLending.updateLendingContractAddress(address(purchaseWithFinancing));
offers.updateLendingContractAddress(address(purchaseWithFinancing));
```

- I was able to establish a mockOpenSea contract, and create a test case that calls `purchaseWithFinancing()`, and purchase an NFT which successfully transfers over the target NFT to the borrower, and emits an event.
- However:
  - I am running into an `Reason: Arithmetic over/underflow` issue that I have no been able to investigate.
  - I was not able to get around the `_requireIsNotSanctioned()` in the testing (this is why it is commented)
  - The above code block probably broke some other tests.

I've included a test file in [`./test/unit/lending/purchaseWithFinancing.t.sol`](./test/unit/lending/purchaseWithFinancing.t.sol)

## OpenSea Resources

- OpenSea Retrieve Listing Docs: https://docs.opensea.io/v2.0/reference/retrieve-listings
- OpenSea API Response: ([Google Docs](https://docs.google.com/document/d/1mXO6AWfKFlxT85IJFGZ-ArQVIbz0zpHl6urfYDWSFB0/edit?usp=sharing)) ([JSON](./os-order-response.json))
- Mapping order response to `BasicOrderParameters`:

```js
{
    // considerationToken
    0x0000000000000000000000000000000000000000,
    // considerationTokenId
    0,
    // considerationAmount
    72000000000000000000,
    // offerer
    0xe5546f0f94b2874fad696c22f3c38d43172edc06,
    // zone
    0x004C00500000aD104D7DBd00e3ae0A5C00560C00,
    // offerToken (BAYC)
    0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D,
    // offerIdentifier
    9095,
    // offerAmount
    1,
    // BasicOrderType
    ETH_TO_ERC721_FULL_OPEN,
    // startTime
    1660796367,
    // endTime
    1660882767,
    // zoneHash
    0x0000000000000000000000000000000000000000000000000000000000000000,
    // salt
    25654833391100762,
    // offererConduitKey
    0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000,
    // fulfillerConduitKey
    0x0000000000000000000000000000000000000000000000000000000000000000,
    // totalOriginalAdditionalRecipients
    2,
    // additionalRecipients
    [
        {
            1800000000000000000,
            0x0000a26b00c1F0DF003000390027140000fAa719
        },
        {
            1800000000000000000,
            0xA858DDc0445d8131daC4d1DE01f834ffcbA52Ef1
        }
    ],
    // signature
    0xd7341b1768e3a7f64d0a249e6c6c0f389cf93ec4293cef1307649b06b979ad072725107f4c7320c070bd1f9676b4a451227da497531fdfac92c26ebff80c1e051b
}

```