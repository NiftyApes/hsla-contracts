# NiftyApes V0 Contracts

This repo comprises the contracts and tests for NiftyApes V0.

Testing is done with forge. Prettier, solhint, slither, can be used to perform further static analysis on the project.

## Running the tests

`forge update`, `forge clean`, and then `forge test --optimize --fork-url $ETH_RPC_URL`

## Linting

`npm run lint` or `npm run lint:check`

## Vulnerability Analysis

`slither --solc-remaps @openzeppelin=lib/openzeppelin-contracts --solc-args optimize src/ --exclude-informational --exclude-optimization --exclude-dependencies --exclude-low`

## Design

The NiftyApes protocol is made up of three core contracts `Liquidity.sol`, `Offers.sol`, and `Lending.sol`. Each is deployed as a seperate contract with references to each other as via interfaces needed. 

`Liquidity.sol` allows for lenders to manage cToken liquidity by depositing and withdrawing, wrapping and unwrapping either `cTokens`, or `ERC20` tokens which are approved for use on the protocol.

`Offers.sol` allows for lenders and borrowers to make lending offers on any asset or collection in existence. This contract manages the NiftyApes on-chain offer book. 

`Lending.sol` allows for lenders and borrowers to execute and refinance loans based on the liquidity and offers in the other two contracts. 