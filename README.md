# NiftyApes V0 Contracts

This repo comprises the contracts and tests for NiftyApes V0.

Testing is done with forge. Prettier, solhint, slither, can be used to perform further static analysis on the project.

## Running the tests

`forge update`, `forge clean`, and then `forge test --optimize --fork-url $ETH_RPC_URL`

Tests can be run offline simply with `forge test`. Some tests do fail but the majority pass and allow development to continue offline.

## Linting

`npm run lint` or `npm run lint:check`

## Vulnerability Analysis

`slither --solc-remaps @openzeppelin=lib/openzeppelin-contracts --solc-args optimize src/ --exclude-informational --exclude-optimization --exclude-dependencies --exclude-low`

## Design

The NiftyApes protocol is made up of four core contracts `Liquidity.sol`, `Offers.sol`, `Lending.sol`, and `SigLending.sol`. Each is deployed as a seperate contract with references to each other as via interfaces needed.

`Liquidity.sol` allows for lenders to manage cToken liquidity by depositing and withdrawing, wrapping and unwrapping either `cTokens`, or `ERC20` tokens which are approved for use on the protocol.

`Offers.sol` allows for lenders and borrowers to make lending offers on any asset or collection in existence. This contract manages the NiftyApes on-chain offer book.

`Lending.sol` allows for lenders and borrowers to execute and refinance loans based on the liquidity and offers in the other two contracts.

`SigLending.sol` allows for lenders and borrowers to execute and refinance loans based on the liquidity and gas-less offers made via signatures and that are stored in a centralized database.

## Deployment

1. Copy `example.env` to a new `.env` file.

2. Add the appropriate values. NEVER USE YOUR OWN KEYS OR KEYS THAT WILL BE USED ON ANY PRODUCTION NETWORK.

3. For local deployment:
   a. In a seperate terminal run `$ anvil`. This will start your local chain. You can then copy an anvil private key.
   b. If you have made any changes to the `.env` run: `$ source .env`
   c. Then run:
   `forge script script/Rinkeby_Deploy_NiftyApes.s.sol:DeployNiftyApesScript --fork-url $LOCAL_RPC_URL --private-key $ANVIL_PRIVATE_KEY --broadcast`

4. For deployment to Rinkeby:
   a. Make sure you have a dedicated test wallet with funding. You can obtain test ETH, ERC20s, and NFTs here: https://faucet.paradigm.xyz/
   b. Add you test wallet private keys to `.env`.
   c. If you have made any changes to the `.env` run: `$ source .env`
   d. Then run:
   `forge script script/Rinkeby_Deploy_NiftyApes.s.sol:DeployNiftyApesScript --optimize --rpc-url $RINKEBY_RPC_URL --private-key $RINKEBY_PRIVATE_KEY --slow --broadcast`

   Rinkeby contract addresses:
   Liquidity: 0x8bC67d5177dD930CD9c9d3cA6Fc33E4f454f30e4
   Offers: 0x9891589826C0e386009819a9DC82e94656036875
   Siglending: 0x13066734874c538606e5589eE9BB6BbC3C018fAF
   Lending: 0xd830dcFC57816aDeB9Bf34A5dA38197810fA8Fd4

5. For deployment to Mainnet:
   a. `forge script script/NiftyApes.s.sol:NiftyApesScript --optimize --slow --rpc-url $MAINNET_RPC_URL --ledger --broadcast`

## Pause

1. To pause Rinkeby protocol:
   a. `forge script script/Rinkeby_PauseProtocol.s.sol:PauseScript --rpc-url $RINKEBY_RPC_URL --ledger --broadcast`

2. To pause Mainnet protocol:
   a. `forge script script/Rinkeby_PauseProtocol.s.sol:PauseScript --rpc-url $MAINNET_RPC_URL --ledger --broadcast`

## Unpause

3. To unpause Rinkeby protocol:
   a. `forge script script/Rinkeby_UnpauseProtocol.s.sol:UnpauseScript --rpc-url $RINKEBY_RPC_URL --ledger --broadcast`

4. To unpause Mainnet protocol:
   a. `forge script script/Rinkeby_UnpauseProtocol.s.sol:UnpauseScript --rpc-url $MAINNET_RPC_URL --ledger --broadcast`

## NiftyApes Error Messages

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
"00019" == "offer.asset and loanAuction.asset do not match"
"00020" == "funds overdrawn"
"00021" == "not nft owner"
"00022" == "offer nftId mismatch"
"00023" == "msg value"
"00024" == "offer creator"
"00025" == "not an improvement"
"00026" == "unexpected terms"
"00027" == "unexpected loan"
"00028" == "msg.sender is not the borrower"
"00029" == "use repayLoan"
"00030" == "msg.value too low"
"00031" == "not authorized"
"00032" == "signature not available"
"00033" == "signer"
"00034" == "insufficient cToken balance"
"00035" == "LendingContract: cannot be address(0)"
"00036" == "LiquidityContract: cannot be address(0)"
"00037" == "cToken mint"
"00038" == "redeemUnderlying failed"
"00039" == "must be greater"
"00040" == "asset allow list"
"00041" == "cAsset allow list"
"00042" == "non matching allow list"
"00043" == "eth not transferable"
"00044" == "max casset"
"00045" == "amount 0"
"00046" == "offer already exists"
"00047" == "not enough value"
"00048" == "seaport fulfillBasicOrder failed"
