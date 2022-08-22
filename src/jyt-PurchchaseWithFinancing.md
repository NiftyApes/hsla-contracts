# Purchase With Financing

Author: [jyturley](https://github.com/jyturley)

## Requirements

- [x] New contract that extends to `Lending.sol`
- [x] New branch: `jyt-purchaseWithFinancing`
- [ ] `purchaseWithFinancingOpenSea()` function
  - [ ] Input: NiftyApes `Offer` struct
  - [ ] Input: OpenSea `BasicOrderParameters` struct
  - [ ] Executes `fullfullBasicOrder()`
  - [ ] Transacts in ETH
- [ ] Optional: unit tests

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

### Known Tradeoffs

## Testing

I've included a test file in [`./test/unit/lending/purchaseWithFinancing.t.sol`](./test/unit/lending/purchaseWithFinancing.t.sol)

## OpenSea Resources

- OpenSea Retrieve Listing Docs: https://docs.opensea.io/v2.0/reference/retrieve-listings
- OpenSea API Response: ([Google Docs](https://docs.google.com/document/d/1mXO6AWfKFlxT85IJFGZ-ArQVIbz0zpHl6urfYDWSFB0/edit?usp=sharing)) ([JSON](./os-order-response.json))
- Mapping order response to `BasicOrderParameters`:

```js
{
    0x0000000000000000000000000000000000000000,
    0,
    72000000000000000000,
    0xe5546f0f94b2874fad696c22f3c38d43172edc06,
    0x004C00500000aD104D7DBd00e3ae0A5C00560C00,
    0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D,
    9095,
    1,
    ETH_TO_ERC721_FULL_OPEN,
    1660796367,
    1660882767,
    0x0000000000000000000000000000000000000000000000000000000000000000,
    25654833391100762,
    0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000,0x0000000000000000000000000000000000000000000000000000000000000000,
    2,
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
    0xd7341b1768e3a7f64d0a249e6c6c0f389cf93ec4293cef1307649b06b979ad072725107f4c7320c070bd1f9676b4a451227da497531fdfac92c26ebff80c1e051b
}

```
