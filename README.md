# NiftyApes V0 Contracts

This repo comprises the contracts and tests for NiftyApes V0.

Testing is done with forge. Prettier, solhint, slither, can be used to perform further static analysis on the project.

## Running the tests

`forge update` and then `forge test --optimize`

## Linting

`npm run lint` or `npm run lint:check`

## Vulnerability Analysis

`slither --solc-remaps @openzeppelin=lib/openzeppelin-contracts --solc-args optimize src/ --exclude-informational --exclude-optimization --exclude-dependencies --exclude-low`

## Tests

For now the tests cover `LiquidityProviders.sol` and `SignatureLendingAuction.sol`, because the other compound math 
will be phased out/refactored.