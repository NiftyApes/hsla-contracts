const { ethers, waffle } = require("hardhat");
const hre = require("hardhat");
const { use, expect } = require("chai");
const { solidity } = require("ethereum-waffle");
const dayjs = require("dayjs");
const Compound = require("@compound-finance/compound-js");
const external_contracts = require("../../react-app/src/contracts/external_contracts");

const DAI_ADDRESS = external_contracts[1].contracts.DAI.address;
const DAI_ABI = external_contracts[1].contracts.DAI.abi;
const C_DAI_ADDRESS = external_contracts[1].contracts.CDAI.address;
const C_DAI_ABI = external_contracts[1].contracts.CDAI.abi;
const C_ETH_ADDRESS = external_contracts[1].contracts.CETH.address;
const C_ETH_ABI = external_contracts[1].contracts.CETH.abi;

use(solidity);

describe("Lending Auctions", function () {
  let owner1 = "";
  let owner2 = "";
  let lender1 = "";
  let lender2 = "";
  let lender3 = "";
  let daiWhale = "";
  let yourCollectible;
  let owner1LendingAuction;
  let owner1YourCollectible;
  let owner2LendingAuction;
  let owner2YourCollectible;
  let owner0LendingAuction;
  let lender1LendingAuction;
  let lender2LendingAuction;
  let lender3LendingAuction;
  let DAITokenContract;
  let cDAITokenContract;
  let cETHTokenContract;

  let now = dayjs().unix();

  describe("Deploy contracts and assign state variables", function () {
    it("Should set owners", async function () {
      let owners = await ethers.getSigners();

      owner1 = owners[1];
      owner2 = owners[2];
      lender1 = owners[9];
      lender2 = owners[8];
      lender3 = owners[7];

      expect(owner1).to.equal(owners[1]);
      expect(owner2).to.equal(owners[2]);
      expect(owner2).to.not.equal(owners[3]);
    });

    it("Should deploy YourCollectible instance", async function () {
      const YourCollectible = await ethers.getContractFactory(
        "YourCollectible"
      );

      yourCollectible = await YourCollectible.deploy();
      expect(yourCollectible).to.exist;
    });

    it("Should deploy Signatureowner0LendingAuction instance", async function () {
      const SignatureLendingAuction = await ethers.getContractFactory(
        "SignatureLendingAuction"
      );

      owner0LendingAuction = await SignatureLendingAuction.deploy();
      expect(owner0LendingAuction).to.exist;
    });
  });

  describe("YourCollectible tests", function () {
    it("Should mint NFTs and transfer to owner1 and owner2", async function () {
      expect(await yourCollectible.balanceOf(owner1.address)).to.equal(0);

      const mintResult = await yourCollectible.mintItem(
        owner1.address,
        "tokenURI"
      );
      await mintResult.wait();

      expect(await yourCollectible.balanceOf(owner1.address)).to.equal(1);
      expect(await yourCollectible.ownerOf(1)).to.equal(owner1.address);

      const mintResult2 = await yourCollectible.mintItem(
        owner2.address,
        "tokenURI"
      );

      await mintResult2.wait();

      expect(await yourCollectible.balanceOf(owner2.address)).to.equal(1);
      expect(await yourCollectible.ownerOf(2)).to.equal(owner2.address);
    });

    it("Should track tokens of owner by index", async function () {
      const tokenBalance = await yourCollectible.balanceOf(owner1.address);
      const token = await yourCollectible.tokenOfOwnerByIndex(
        owner1.address,
        tokenBalance.sub(1)
      );
      expect(token.toNumber()).to.greaterThan(0);
    });
  });

  describe("SignatureLendingAuction", function () {
    describe("LiquidityProviders tests", function () {
      it("Should impersonate DAI whale and instantiate lender1 contract", async function () {
        await hre.network.provider.request({
          method: "hardhat_impersonateAccount",
          params: ["0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503"],
        });

        daiWhale = await ethers.provider.getSigner(
          "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503"
        );
        daiWhale.address = daiWhale._address;

        expect(daiWhale.address).to.equal(
          "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503"
        );

        lender1LendingAuction = owner0LendingAuction.connect(lender1);

        expect(lender1LendingAuction).to.exist;
      });

      it("Should set DAI to cDAI address", async function () {
        let setCAssetAddressResult1 =
          await lender1LendingAuction.setCAssetAddress(
            // assetAddress - DAI
            "0x6b175474e89094c44da98b954eedeac495271d0f",
            // cAssetAddress - cDAI
            "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643"
          );

        // transaction fails as expected when lender1 signs transaction, but chai does not seem to be able to catch failure.
        // console.log("setCAssetAddressResult1", setCAssetAddressResult1);
        // await setCAssetAddressResult1.wait();

        // expect(setCAssetAddressResult1).to.fail();

        let setCAssetAddressResult =
          await owner0LendingAuction.setCAssetAddress(
            // assetAddress - DAI
            "0x6b175474e89094c44da98b954eedeac495271d0f",
            // cAssetAddress - cDAI
            "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643"
          );
        await setCAssetAddressResult.wait();

        let assetToCAssetResult = await owner0LendingAuction.assetToCAsset(
          "0x6b175474e89094c44da98b954eedeac495271d0f"
        );

        expect(assetToCAssetResult.toLowerCase()).to.equal(
          "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643"
        );
      });

      it("daiWhale should send DAI and cDAI to Lender1", async function () {
        // hardhat cant seem to sign a message from an impersonated account because it doesnt have access to the
        // private key, not sure if bug or by design, but need to work around by sending DAI and cDAI to generated account
        DAIWhaleTokenContract = await new ethers.Contract(
          DAI_ADDRESS,
          DAI_ABI,
          daiWhale
        );
        expect(DAIWhaleTokenContract).to.exist;

        let daiTransfer = await DAIWhaleTokenContract.transfer(
          lender1.address,
          "10000000000000000000"
        );

        await daiTransfer.wait();

        let daiBalance = await DAIWhaleTokenContract.balanceOf(lender1.address);

        expect(daiBalance).to.equal("10000000000000000000");

        CDAIWhaleTokenContract = await new ethers.Contract(
          C_DAI_ADDRESS,
          C_DAI_ABI,
          daiWhale
        );
        expect(CDAIWhaleTokenContract).to.exist;

        let cDaiTransfer = await CDAIWhaleTokenContract.transfer(
          lender1.address,
          "100000000000"
        );

        await cDaiTransfer.wait();

        let cDaiBalance = await CDAIWhaleTokenContract.balanceOf(
          lender1.address
        );

        expect(cDaiBalance).to.equal("100000000000");
      });

      it("Lender1 should approve DAI for deposit", async function () {
        DAITokenContract = await new ethers.Contract(
          DAI_ADDRESS,
          DAI_ABI,
          lender1
        );
        expect(DAITokenContract).to.exist;

        let approval = await DAITokenContract.approve(
          lender1LendingAuction.address,
          "10000000000000000000"
        );

        await approval.wait();

        let allowance = await DAITokenContract.allowance(
          lender1.address,
          lender1LendingAuction.address
        );

        expect(allowance).to.equal("10000000000000000000");
      });

      it("Lender1 should supplyErc20", async function () {
        cDAITokenContract = await new ethers.Contract(
          C_DAI_ADDRESS,
          C_DAI_ABI,
          lender1
        );
        expect(cDAITokenContract).to.exist;

        let lender1PreTxBalance = await lender1LendingAuction.cAssetBalances(
          "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643",
          lender1.address
        );

        expect(lender1PreTxBalance).to.equal("0");

        let supplyErc20 = await lender1LendingAuction.supplyErc20(
          "0x6B175474E89094C44Da98b954EedeAC495271d0F",
          "10000000000000000000"
        );

        let supplyErc20Result = await supplyErc20.wait();

        // not sure how to test return value of function.
        // supplyErc20 and supplyErc20Result both return transaction objects instaed of expected value.
        // console.log("supplyErc20Result", supplyErc20Result);

        let lender1PostTxBalance = await lender1LendingAuction.cAssetBalances(
          "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643",
          lender1.address
        );

        let protocolPostTxBalance = await cDAITokenContract.balanceOf(
          lender1LendingAuction.address
        );

        // expect(protocolPostTxBalance).to.equal(supplyErc20Result);
        expect(protocolPostTxBalance).to.equal(lender1PostTxBalance);
      });

      // it("Lender1 should approve cDAI for deposit", async function () {
      //   let approval = await cDAITokenContract.approve(
      //     lender1LendingAuction.address,
      //     "200000000"
      //   );

      //   await approval.wait();

      //   let allowance = await cDAITokenContract.allowance(
      //     lender1.address,
      //     lender1LendingAuction.address
      //   );

      //   expect(allowance).to.equal("200000000");
      // });

      // it("Lender1 should supplyCErc20", async function () {
      //   let supplyCErc20 = await lender1LendingAuction.supplyCErc20(
      //     "0x6B175474E89094C44Da98b954EedeAC495271d0F",
      //     "200000000"
      //   );

      //   let supplyCErc20Result = await supplyCErc20.wait();

      //   let lender1PostTxBalance = await lender1LendingAuction.cAssetBalances(
      //     "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643",
      //     lender1.address
      //   );

      //   let protocolPostTxBalance = await cDAITokenContract.balanceOf(
      //     lender1LendingAuction.address
      //   );

      //   expect(protocolPostTxBalance).to.equal(lender1PostTxBalance);
      // });

      // it("Lender1 should withdrawErc20 based on erc20 amount", async function () {
      //   let withdrawErc20 = await lender1LendingAuction.withdrawErc20(
      //     "0x6B175474E89094C44Da98b954EedeAC495271d0F",
      //     false,
      //     "1000000000000000000"
      //   );

      //   await withdrawErc20.wait();

      //   let lender1PostTxBalance = await lender1LendingAuction.cAssetBalances(
      //     "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643",
      //     lender1.address
      //   );

      //   let protocolPostTxBalance = await cDAITokenContract.balanceOf(
      //     lender1LendingAuction.address
      //   );

      //   expect(protocolPostTxBalance).to.equal(lender1PostTxBalance);
      // });

      // it("Lender1 should withdrawErc20 based on cErc20 amount", async function () {
      //   let withdrawErc20 = await lender1LendingAuction.withdrawErc20(
      //     "0x6B175474E89094C44Da98b954EedeAC495271d0F",
      //     "true",
      //     "100000000"
      //   );

      //   await withdrawErc20.wait();

      //   let lender1PostTxBalance = await lender1LendingAuction.cAssetBalances(
      //     "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643",
      //     lender1.address
      //   );

      //   let protocolPostTxBalance = await cDAITokenContract.balanceOf(
      //     lender1LendingAuction.address
      //   );

      //   // math in withdrawErc20 function rounds down, while math in Compound function rounds up. Values are off by one.
      //   expect(protocolPostTxBalance.toNumber()).to.equal(
      //     lender1PostTxBalance.toNumber() + 1
      //   );
      // });

      // it("Lender1 should withdrawCErc20", async function () {
      //   let withdrawErc20 = await lender1LendingAuction.withdrawCErc20(
      //     "0x6B175474E89094C44Da98b954EedeAC495271d0F",
      //     "100000000"
      //   );

      //   await withdrawErc20.wait();

      //   let lender1PostTxBalance = await lender1LendingAuction.cAssetBalances(
      //     "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643",
      //     lender1.address
      //   );

      //   let protocolPostTxBalance = await cDAITokenContract.balanceOf(
      //     lender1LendingAuction.address
      //   );

      //   // added "1" in previous test so must compensate in this test as well
      //   expect(protocolPostTxBalance.toNumber()).to.equal(
      //     lender1PostTxBalance.toNumber() + 1
      //   );
      // });

      // it("Should set ETH to cETH address", async function () {
      //   let setCAssetAddressResult = await owner0LendingAuction.setCAssetAddress(
      //     // assetAddress - ETH
      //     "0x0000000000000000000000000000000000000000",
      //     // cAssetAddress - cETH
      //     "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5"
      //   );
      //   await setCAssetAddressResult.wait();

      //   let assetToCAssetResult = await owner0LendingAuction.assetToCAsset(
      //     "0x0000000000000000000000000000000000000000"
      //   );

      //   expect(assetToCAssetResult).to.equal(
      //     "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5"
      //   );
      // });

      // it("Should impersonate cETH whale and instantiate lender2 contract", async function () {
      //   await hre.network.provider.request({
      //     method: "hardhat_impersonateAccount",
      //     params: ["0x8aceab8167c80cb8b3de7fa6228b889bb1130ee8"],
      //   });

      //   lender2 = await ethers.provider.getSigner(
      //     "0x8aceab8167c80cb8b3de7fa6228b889bb1130ee8"
      //   );
      //   lender2.address = lender2._address;

      //   expect(lender2.address.toLowerCase()).to.equal(
      //     "0x8aceab8167c80cb8b3de7fa6228b889bb1130ee8"
      //   );

      //   lender2LendingAuction = owner0LendingAuction.connect(lender2);

      //   expect(lender2LendingAuction).to.exist;
      // });

      // it("Lender2 should supplyEth", async function () {
      //   cETHTokenContract = await new ethers.Contract(
      //     C_ETH_ADDRESS,
      //     C_ETH_ABI,
      //     lender2
      //   );
      //   expect(cETHTokenContract).to.exist;

      //   let lender2PreTxBalance = await lender2LendingAuction.cAssetBalances(
      //     "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5",
      //     lender2.address
      //   );

      //   expect(lender2PreTxBalance).to.equal("0");

      //   let supplyEth = await lender2LendingAuction.supplyEth({
      //     value: "1000000000000000000",
      //   });

      //   await supplyEth.wait();

      //   let lender2PostTxBalance = await lender2LendingAuction.cAssetBalances(
      //     "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5",
      //     lender2.address
      //   );

      //   let protocolPostTxBalance = await cETHTokenContract.balanceOf(
      //     lender2LendingAuction.address
      //   );

      //   expect(protocolPostTxBalance).to.equal(lender2PostTxBalance);
      // });

      // it("lender2 should approve cETH for deposit", async function () {
      //   let approval = await cETHTokenContract.approve(
      //     lender2LendingAuction.address,
      //     "200000000"
      //   );

      //   await approval.wait();

      //   let allowance = await cETHTokenContract.allowance(
      //     lender2.address,
      //     lender2LendingAuction.address
      //   );

      //   expect(allowance).to.equal("200000000");
      // });

      // it("lender2 should supplyCEth", async function () {
      //   let supplyCEth = await lender2LendingAuction.supplyCEth("200000000");

      //   let supplyCEthResult = await supplyCEth.wait();

      //   let lender2PostTxBalance = await lender2LendingAuction.cAssetBalances(
      //     "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5",
      //     lender2.address
      //   );

      //   let protocolPostTxBalance = await cETHTokenContract.balanceOf(
      //     lender2LendingAuction.address
      //   );

      //   expect(protocolPostTxBalance).to.equal(lender2PostTxBalance);
      // });

      // it("lender2 should withdrawEth based on eth amount", async function () {
      //   let withdrawEth = await lender2LendingAuction.withdrawEth(
      //     false,
      //     "1000000000000000000"
      //   );

      //   let withdrawEthResult = await withdrawEth.wait();

      //   let lender2PostTxBalance = await lender2LendingAuction.cAssetBalances(
      //     "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5",
      //     lender2.address
      //   );

      //   let protocolPostTxBalance = await cETHTokenContract.balanceOf(
      //     lender2LendingAuction.address
      //   );

      //   expect(protocolPostTxBalance).to.equal(lender2PostTxBalance);
      // });

      // it("lender2 should withdrawEth based on cEth amount", async function () {
      //   let withdrawEth = await lender2LendingAuction.withdrawEth(
      //     "true",
      //     "100000000"
      //   );

      //   let withdrawEthResult = await withdrawEth.wait();

      //   let lender2PostTxBalance = await lender2LendingAuction.cAssetBalances(
      //     "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5",
      //     lender2.address
      //   );

      //   let protocolPostTxBalance = await cETHTokenContract.balanceOf(
      //     lender2LendingAuction.address
      //   );

      //   // math in withdrawEth function rounds down, while math in Compound function rounds up. Values are off by one.
      //   expect(protocolPostTxBalance.toNumber()).to.equal(
      //     lender2PostTxBalance.toNumber() + 1
      //   );
      // });

      // it("lender2 should withdrawCEth", async function () {
      //   let withdrawEth = await lender2LendingAuction.withdrawCEth("100000000");

      //   await withdrawEth.wait();

      //   let lender2PostTxBalance = await lender2LendingAuction.cAssetBalances(
      //     "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5",
      //     lender2.address
      //   );

      //   let protocolPostTxBalance = await cETHTokenContract.balanceOf(
      //     lender2LendingAuction.address
      //   );

      //   // added "1" in previous test so must compensate in this test as well
      //   expect(protocolPostTxBalance.toNumber()).to.equal(
      //     lender2PostTxBalance.toNumber() + 1
      //   );
      // });
    });

    describe("LiquidityProviders tests", function () {
      let offerHash1;
      let offerHash2;
      let signature1;
      let signature2;

      it("Should provide correct hash", async function () {
        offerHash1 = await lender1LendingAuction.getOfferHash({
          // nft contract address
          nftContractAddress: yourCollectible.address,
          // nftId
          nftId: 1,
          // asset Address
          asset: "0x6b175474e89094c44da98b954eedeac495271d0f",
          // loanAmount
          amount: "1000000000000000000",
          // interest rate
          interestRate: 1,
          // duration in seconds
          duration: 86400,
          // expiration
          expiration: "1740097934",
          // fixedTerms
          fixedTerms: false,
          // floorTerm
          floorTerm: false,
        });

        expect(offerHash1).to.equal(
          "0xc9382e7a1ecf5f7938593187347b40efdda6b721a69d67a212e7cd0963d71c5c"
        );
      });

      it("Should create proper bid signature by lender", async function () {
        signature1 = await lender1.signMessage(
          ethers.utils.arrayify(offerHash1)
        );

        expect(signature1).to.equal(
          "0x81a6d0c11d05a6d66e8e28ad702020873935bb82c5278a8622da8bc80725506449c0a557e420a0d58d37a65f0065a17381ebb80e7bb555df7651eeec92a8ceb31c"
        );

        const signer1 = await lender1LendingAuction.getOfferSigner(
          "0xc9382e7a1ecf5f7938593187347b40efdda6b721a69d67a212e7cd0963d71c5c",
          "0x81a6d0c11d05a6d66e8e28ad702020873935bb82c5278a8622da8bc80725506449c0a557e420a0d58d37a65f0065a17381ebb80e7bb555df7651eeec92a8ceb31c"
        );

        expect(signer1).to.equal(lender1.address);
      });

      it("Should approve NFT for loan and executeLoanByBid", async function () {
        owner1LendingAuction = owner0LendingAuction.connect(owner1);

        expect(owner1LendingAuction).to.exist;

        owner1YourCollectible = yourCollectible.connect(owner1);

        expect(owner1LendingAuction).to.exist;

        // could also use setApprovalForAll()
        const approveNft = await owner1YourCollectible.approve(
          owner1LendingAuction.address,
          1
        );

        await approveNft.wait();

        const approved = await owner1YourCollectible.getApproved(1);

        console.log("approved", approved);

        expect(approved).to.equal(owner1LendingAuction.address);

        const executeLoanByBid1 = await owner1LendingAuction.executeLoanByBid(
          {
            // nft contract address
            nftContractAddress: yourCollectible.address,
            // nftId
            nftId: 1,
            // asset Address
            asset: "0x6b175474e89094c44da98b954eedeac495271d0f",
            // loanAmount
            amount: "1000000000000000000",
            // interest rate
            interestRate: 1,
            // duration in seconds
            duration: 86400,
            // expiration (arbitrary date in the reasonably distant future)
            expiration: "1740097934",
            // fixedTerms
            fixedTerms: false,
            // floorTerm
            floorTerm: false,
          },
          signature1,
          1
        );

        await executeLoanByBid1.wait();

        const loanAuctionData1 = await owner1LendingAuction.loanAuctions(
          yourCollectible.address,
          1
        );

        const erc721Owner = await owner1YourCollectible.ownerOf(1);

        const activeLoan721Owner = await owner1LendingAuction.ownerOf(
          owner1YourCollectible.address,
          1
        );

        expect(erc721Owner).to.equal(owner1LendingAuction.address);
        expect(loanAuctionData1.nftOwner).to.equal(activeLoan721Owner);
        expect(loanAuctionData1.lender).to.equal(lender1.address);
        expect(loanAuctionData1.asset.toLowerCase()).to.equal(
          "0x6b175474e89094c44da98b954eedeac495271d0f"
        );
        expect(loanAuctionData1.amount).to.equal("1000000000000000000");
        expect(loanAuctionData1.interestRate).to.equal(1);
        expect(loanAuctionData1.duration).to.equal("86400");
        expect(loanAuctionData1.historicInterest).to.equal(0);
        // pegged blocktime gives us a stable value to test against
        expect(loanAuctionData1.bestBidTime).to.be.within(
          1641156300,
          1641156300 + 30
        );
        expect(loanAuctionData1.loanExecutedTime).to.be.within(
          1641156300,
          1641156300 + 30
        );
        expect(loanAuctionData1.amountDrawn).to.equal("1000000000000000000");
        expect(loanAuctionData1.timeDrawn).to.equal("86400");
        expect(loanAuctionData1.fixedTerms).to.equal(false);
      });

      it("Should create proper ask signature by owner2", async function () {
        owner2LendingAuction = owner0LendingAuction.connect(owner2);

        expect(owner2LendingAuction).to.exist;

        offerHash2 = await owner2LendingAuction.getOfferHash({
          // nft contract address
          nftContractAddress: yourCollectible.address,
          // nftId
          nftId: 2,
          // asset Address
          asset: "0x6b175474e89094c44da98b954eedeac495271d0f",
          // loanAmount
          amount: "1000000000000000000",
          // interest rate
          interestRate: 1,
          // duration in seconds
          duration: 86400,
          // expiration
          expiration: "1740097934",
          // fixedTerms
          fixedTerms: false,
          // floorTerm
          floorTerm: false,
        });

        expect(offerHash2).to.equal(
          "0x0ee7c08519e8cac4d8ba3b8a64533430ad87c82c7040424197afab7fb9a6c5e3"
        );

        signature2 = await owner2.signMessage(
          ethers.utils.arrayify(offerHash2)
        );

        expect(signature2).to.equal(
          "0xe0c6c7a486fbfade121898efb45f61f221b6aa45d746bfd9dde86c505665989d686d5854e14cb571cb5f9aea66a239f510bd798c9de7987bf42cb270a053145a1b"
        );

        const signer2 = await owner2LendingAuction.getOfferSigner(
          "0x0ee7c08519e8cac4d8ba3b8a64533430ad87c82c7040424197afab7fb9a6c5e3",
          "0xe0c6c7a486fbfade121898efb45f61f221b6aa45d746bfd9dde86c505665989d686d5854e14cb571cb5f9aea66a239f510bd798c9de7987bf42cb270a053145a1b"
        );

        expect(signer2).to.equal(owner2.address);
      });

      it("Should approve NFT for loan and executeLoanByAsk", async function () {
        owner2YourCollectible = yourCollectible.connect(owner2);

        expect(owner2YourCollectible).to.exist;

        // could also use setApprovalForAll()
        const approveNft = await owner2YourCollectible.approve(
          owner2LendingAuction.address,
          2
        );

        await approveNft.wait();

        const approved = await owner2YourCollectible.getApproved(2);

        expect(approved).to.equal(owner2LendingAuction.address);

        const executeLoanByBid2 = await lender1LendingAuction.executeLoanByAsk(
          {
            // nft contract address
            nftContractAddress: yourCollectible.address,
            // nftId
            nftId: 2,
            // asset Address
            asset: "0x6b175474e89094c44da98b954eedeac495271d0f",
            // loanAmount
            amount: "1000000000000000000",
            // interest rate
            interestRate: 1,
            // duration in seconds
            duration: 86400,
            // expiration (arbitrary date in the reasonably distant future)
            expiration: "1740097934",
            // fixedTerms
            fixedTerms: false,
            // floorTerm
            floorTerm: false,
          },
          signature2
        );

        await executeLoanByBid2.wait();

        const loanAuctionData2 = await lender1LendingAuction.loanAuctions(
          yourCollectible.address,
          2
        );

        const erc721Owner = await owner2YourCollectible.ownerOf(1);

        const activeLoan721Owner = await lender1LendingAuction.ownerOf(
          owner2YourCollectible.address,
          2
        );

        expect(erc721Owner).to.equal(lender1LendingAuction.address);
        expect(loanAuctionData2.nftOwner).to.equal(activeLoan721Owner);
        expect(loanAuctionData2.lender).to.equal(lender1.address);
        expect(loanAuctionData2.asset.toLowerCase()).to.equal(
          "0x6b175474e89094c44da98b954eedeac495271d0f"
        );
        expect(loanAuctionData2.amount).to.equal("1000000000000000000");
        expect(loanAuctionData2.interestRate).to.equal(1);
        expect(loanAuctionData2.duration).to.equal("86400");
        expect(loanAuctionData2.historicInterest).to.equal(0);
        expect(loanAuctionData2.bestBidTime).to.be.within(
          1641156300,
          1641156300 + 30
        );
        expect(loanAuctionData2.loanExecutedTime).to.be.within(
          1641156300,
          1641156300 + 30
        );
        expect(loanAuctionData2.amountDrawn).to.equal("1000000000000000000");
        expect(loanAuctionData2.timeDrawn).to.equal("86400");
        expect(loanAuctionData2.fixedTerms).to.equal(false);
      });
    });
  });

  // describe("Lending Auction tests", function () {
  //   it("Should create a new bestBid on an auction that has no bid/ask history", async function () {
  //     const newBestBid = await owner0LendingAuction.bid(
  //       // nft contract address
  //       yourCollectible.address,
  //       // nftId
  //       1,
  //       // interest rate
  //       10,
  //       // duration in seconds
  //       1,
  //       // value of loan in wei
  //       { value: 1 }
  //     );

  //     let newBestBidResult = await owner0LendingAuction.loanAuctions(
  //       yourCollectible.address,
  //       1
  //     );
  //     expect(newBestBidResult.bestBidder).to.equal(owner0);
  //     expect(newBestBidResult.bestBidInterestRate).to.equal(10);
  //     expect(newBestBidResult.bestBidLoanDuration).to.equal(1);
  //     expect(newBestBidResult.bestBidLoanAmount).to.equal(1);

  //     await expect(newBestBid)
  //       .to.emit(owner0LendingAuction, "NewBestBid")
  //       .withArgs(owner0, yourCollectible.address, 1, 1, 10, 1);
  //   });

  //   it("Should revert bid with `Bid must have better terms`. No terms changed.", async function () {
  //     await expect(
  //       owner0LendingAuction.bid(
  //         // nft contract address
  //         yourCollectible.address,
  //         // nftId
  //         1,
  //         // interest rate
  //         10,
  //         // duration in seconds
  //         1,
  //         // value of loan in wei
  //         { value: 1 }
  //       )
  //     ).to.be.revertedWith("Bid must have better terms than current best bid");
  //   });

  //   it("Should create a new bestBid with a higher loan amount", async function () {
  //     const newBestBid = await owner0LendingAuction.bid(
  //       // nft contract address
  //       yourCollectible.address,
  //       // nftId
  //       1,
  //       // interest rate
  //       10,
  //       // duration in seconds
  //       1,
  //       // value of loan in wei
  //       { value: 2 }
  //     );

  //     let newBestBidResult = await owner0LendingAuction.loanAuctions(
  //       yourCollectible.address,
  //       1
  //     );
  //     expect(newBestBidResult.bestBidder).to.equal(owner0);
  //     expect(newBestBidResult.bestBidInterestRate).to.equal(10);
  //     expect(newBestBidResult.bestBidLoanDuration).to.equal(1);
  //     expect(newBestBidResult.bestBidLoanAmount).to.equal(2);
  //   });

  //   it("Should revert bid with `Bid must have better terms`. Better interest rate, worse loan amount", async function () {
  //     await expect(
  //       owner0LendingAuction.bid(
  //         // nft contract address
  //         yourCollectible.address,
  //         // nftId
  //         1,
  //         // interest rate
  //         9,
  //         // duration in seconds
  //         1,
  //         // value of loan in wei
  //         { value: 1 }
  //       )
  //     ).to.be.revertedWith("Bid must have better terms than current best bid");
  //   });

  //   it("Should create a new bestBid with a lower interest rate", async function () {
  //     const newBestBid = await owner0LendingAuction.bid(
  //       // nft contract address
  //       yourCollectible.address,
  //       // nftId
  //       1,
  //       // interest rate
  //       9,
  //       // duration in seconds
  //       1,
  //       // value of loan in wei
  //       { value: 2 }
  //     );

  //     let newBestBidResult = await owner0LendingAuction.loanAuctions(
  //       yourCollectible.address,
  //       1
  //     );
  //     expect(newBestBidResult.bestBidder).to.equal(owner0);
  //     expect(newBestBidResult.bestBidInterestRate).to.equal(9);
  //     expect(newBestBidResult.bestBidLoanDuration).to.equal(1);
  //     expect(newBestBidResult.bestBidLoanAmount).to.equal(2);
  //   });

  //   it("Should revert bid with `Bid must have better terms`. Better loan duration, worse interest rate.", async function () {
  //     await expect(
  //       owner0LendingAuction.bid(
  //         // nft contract address
  //         yourCollectible.address,
  //         // nftId
  //         1,
  //         // interest rate
  //         10,
  //         // duration in seconds
  //         2,
  //         // value of loan in wei
  //         { value: 2 }
  //       )
  //     ).to.be.revertedWith("Bid must have better terms than current best bid");
  //   });

  //   it("Should create a new bestBid with a longer loan duration", async function () {
  //     const newBestBid = await owner0LendingAuction.bid(
  //       // nft contract address
  //       yourCollectible.address,
  //       // nftId
  //       1,
  //       // interest rate
  //       9,
  //       // duration in seconds
  //       2,
  //       // value of loan in wei
  //       { value: 2 }
  //     );

  //     let newBestBidResult = await owner0LendingAuction.loanAuctions(
  //       yourCollectible.address,
  //       1
  //     );
  //     expect(newBestBidResult.bestBidder).to.equal(owner0);
  //     expect(newBestBidResult.bestBidInterestRate).to.equal(9);
  //     expect(newBestBidResult.bestBidLoanDuration).to.equal(2);
  //     expect(newBestBidResult.bestBidLoanAmount).to.equal(2);
  //   });
  // });
});
