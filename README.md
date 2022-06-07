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

## Lending.sol Error Messages

"00001" == "lender balance"
"00002" == "max fee"
"00003" == "signature unsupported"
"00004" == "no offer"
"00005" == "offer amount"
"00006" == "Loan already open"
"00007" == "loan not active"
"00008" == "loan not expired"
"00009" == "loan expired"
"00010" == "offer expired"
"00011" == "offer duration"
"00012" == "lender offer"
"00013" == "borrower offer"
"00014" == "floor term"
"00015" == "fixed term loan"
"00016" == "fixed term offer"
"00017" == "sanctioned address"
"00018" == "721 owner"
"00019" == "asset mismatch"
"00020" == "funds overdrawn"
"00021" == "nft owner"
"00022" == "offer nftId mismatch"
"00023" == "msg value"
"00024" == "offer creator"
"00025" == "not an improvement"
"00026" == "unexpected terms"
"00027" == "unexpected loan"
"00028" == "msg.sender is not the borrower"
"00029" == "use repayLoan"
"00030" == "msg.value too low"
