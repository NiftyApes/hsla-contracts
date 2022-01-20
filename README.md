# NiftyApes V0 Contracts

This repo comprises the contracts and tests for NiftyApes V0.

Testing is done with forge. Prettier, solhint, slither, can be used to perform further static analysis on the project.

## Running the tests

`forge update` and then `forge test --optimize --fork-url $ETH_RPC_URL`

## Linting

`npm run lint` or `npm run lint:check`

## Vulnerability Analysis

`slither --solc-remaps @openzeppelin=lib/openzeppelin-contracts --solc-args optimize src/ --exclude-informational --exclude-optimization --exclude-dependencies --exclude-low`

## Design

`LiquidityProviders.sol` exposes interfaces for lenders to manage cToken liquidity by depositing and withdrawing, 
wrapping and unwrapping either `cTokens`, or `ERC20` tokens which are approved for use on the protocol.

`SignatureLendingAuction.sol` inherits from `LiquidityProviders` and adds interfaces for a signature based lending 
auction between lenders and NFT holders.