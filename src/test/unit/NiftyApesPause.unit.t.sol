// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../interfaces/compound/ICERC20.sol";
import "../../interfaces/compound/ICEther.sol";
import "../../Lending.sol";
import "../../Liquidity.sol";
import "../../Offers.sol";
import "../../SigLending.sol";
import "../../purchaseWithFinancing/PurchaseWithFinancing.sol";
import "../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../interfaces/niftyapes/offers/IOffersStructs.sol";

import "../common/BaseTest.sol";
import "../mock/CERC20Mock.sol";
import "../mock/CEtherMock.sol";
import "../mock/ERC20Mock.sol";
import "../mock/ERC721Mock.sol";
import "../mock/SeaportMock.sol";
import "../mock/SudoswapFactoryMock.sol";
import "../mock/SudoswapRouterMock.sol";

contract NiftyApesPauseUnitTest is
    BaseTest,
    ILendingStructs,
    IOffersStructs,
    ERC721HolderUpgradeable
{
    NiftyApesLending lendingAuction;
    NiftyApesOffers offersContract;
    NiftyApesLiquidity liquidityProviders;
    NiftyApesSigLending sigLendingAuction;
    NiftyApesPurchaseWithFinancing purchaseWithFinancing;
    SeaportMock seaportMock;
    LSSVMPairFactoryMock sudoswapFactoryMock;
    LSSVMRouterMock sudoswapRouterMock;
    ERC20Mock daiToken;
    CERC20Mock cDAIToken;
    CEtherMock cEtherToken;
    address compContractAddress = 0xbbEB7c67fa3cfb40069D19E598713239497A3CA5;

    ERC721Mock mockNft;

    bool acceptEth;

    address constant ZERO_ADDRESS = address(0);
    address constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address constant LENDER_1 = address(0x1010);
    address constant LENDER_2 = address(0x2020);
    address constant BORROWER_1 = address(0x101);

    receive() external payable {
        require(acceptEth, "acceptEth");
    }

    function setUp() public {
        seaportMock = new SeaportMock();
        sudoswapFactoryMock = new LSSVMPairFactoryMock();
        sudoswapRouterMock = new LSSVMRouterMock();

        purchaseWithFinancing = new NiftyApesPurchaseWithFinancing();
        purchaseWithFinancing.initialize(
            address(seaportMock),
            address(sudoswapFactoryMock),
            address(sudoswapRouterMock)
        );

        liquidityProviders = new NiftyApesLiquidity();
        liquidityProviders.initialize(compContractAddress, address(purchaseWithFinancing));

        offersContract = new NiftyApesOffers();
        offersContract.initialize(address(liquidityProviders), address(purchaseWithFinancing));

        sigLendingAuction = new NiftyApesSigLending();
        sigLendingAuction.initialize(address(offersContract), address(purchaseWithFinancing));

        lendingAuction = new NiftyApesLending();
        lendingAuction.initialize(
            address(liquidityProviders),
            address(offersContract),
            address(sigLendingAuction),
            address(purchaseWithFinancing)
        );

        offersContract.updateLendingContractAddress(address(lendingAuction));

        daiToken = new ERC20Mock();
        daiToken.initialize("USD Coin", "DAI");
        cDAIToken = new CERC20Mock();
        cDAIToken.initialize(daiToken);
        liquidityProviders.setCAssetAddress(address(daiToken), address(cDAIToken));

        cEtherToken = new CEtherMock();
        cEtherToken.initialize();
        liquidityProviders.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        lendingAuction.pause();
        liquidityProviders.pause();
        offersContract.pause();
        sigLendingAuction.pause();

        acceptEth = true;

        mockNft = new ERC721Mock();
        mockNft.initialize("BoredApe", "BAYC");

        mockNft.safeMint(address(this), 1);
        mockNft.approve(address(lendingAuction), 1);

        mockNft.safeMint(address(this), 2);
        mockNft.approve(address(lendingAuction), 2);
    }

    function getOffer() internal view returns (Offer memory offer) {
        return
            Offer({
                creator: address(0x0000000000000000000000000000000000000001),
                nftContractAddress: address(0x0000000000000000000000000000000000000002),
                interestRatePerSecond: 3,
                fixedTerms: false,
                floorTerm: false,
                lenderOffer: true,
                nftId: 4,
                asset: address(daiToken),
                amount: 6,
                duration: 7,
                expiration: 8
            });
    }

    function testCannotPause_not_owner() public {
        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Ownable: caller is not the owner");

        lendingAuction.pause();
    }

    function testCannotUnpause_not_owner() public {
        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Ownable: caller is not the owner");

        lendingAuction.unpause();
    }

    function testCannotPauseLiquidityProviders_not_owner() public {
        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Ownable: caller is not the owner");

        liquidityProviders.pause();
    }

    function testCannotUnpauseLiquidityProviders_not_owner() public {
        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Ownable: caller is not the owner");

        liquidityProviders.unpause();
    }

    function testCannotPauseOffersContract_not_owner() public {
        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Ownable: caller is not the owner");

        offersContract.pause();
    }

    function testCannotUnpauseOffersContract_not_owner() public {
        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Ownable: caller is not the owner");

        offersContract.unpause();
    }

    function testCannotPauseSigLendingAuction_not_owner() public {
        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Ownable: caller is not the owner");

        sigLendingAuction.pause();
    }

    function testCannotUnpauseSigLendingAuction_not_owner() public {
        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Ownable: caller is not the owner");

        sigLendingAuction.unpause();
    }

    function testCannotSupplyErc20_paused() public {
        hevm.expectRevert("Pausable: paused");

        liquidityProviders.supplyErc20(address(daiToken), 1);
    }

    function testCannotSupplyCErc20_paused() public {
        hevm.expectRevert("Pausable: paused");

        liquidityProviders.supplyCErc20(address(cDAIToken), 1);
    }

    function testCannotWithdrawErc20_paused() public {
        hevm.expectRevert("Pausable: paused");

        liquidityProviders.withdrawErc20(address(daiToken), 1);
    }

    function testCannotwithdrawCErc20_paused() public {
        hevm.expectRevert("Pausable: paused");

        liquidityProviders.withdrawCErc20(address(cDAIToken), 1);
    }

    function testCannotSupplyEth_paused() public {
        hevm.expectRevert("Pausable: paused");

        liquidityProviders.supplyEth();
    }

    function testCannotWithdrawEth_paused() public {
        hevm.expectRevert("Pausable: paused");

        liquidityProviders.withdrawEth(1);
    }

    function testCannotExecuteLoanByBorrower_paused() public {
        hevm.expectRevert("Pausable: paused");

        lendingAuction.executeLoanByBorrower(address(0), 1, bytes32(0), false);
    }

    function testCannotExecuteLoanByBorrowerSignature_paused() public {
        hevm.expectRevert("Pausable: paused");

        sigLendingAuction.executeLoanByBorrowerSignature(getOffer(), "", 0);
    }

    function testCannotExecuteLoanByLender_paused() public {
        hevm.expectRevert("Pausable: paused");

        lendingAuction.executeLoanByLender(address(0), 1, bytes32(0), false);
    }

    function testCannotExecuteLoanByLenderSignature_paused() public {
        hevm.expectRevert("Pausable: paused");

        sigLendingAuction.executeLoanByLenderSignature(getOffer(), "");
    }

    function testCannotRefinanceByBorrower_paused() public {
        hevm.expectRevert("Pausable: paused");

        lendingAuction.refinanceByBorrower(
            address(0),
            1,
            false,
            bytes32(0),
            uint32(block.timestamp)
        );
    }

    function testCannotRefinanceByBorrowerSignature_paused() public {
        hevm.expectRevert("Pausable: paused");

        sigLendingAuction.refinanceByBorrowerSignature(getOffer(), "", 1, uint32(block.timestamp));
    }

    function testCannotRefinanceByLender_paused() public {
        hevm.expectRevert("Pausable: paused");

        lendingAuction.refinanceByLender(getOffer(), 0);
    }

    function testCannotDrawLoanAmount_paused() public {
        hevm.expectRevert("Pausable: paused");

        lendingAuction.drawLoanAmount(address(0), 1, 2);
    }

    function testCannotRepayLoan_paused() public {
        hevm.expectRevert("Pausable: paused");

        lendingAuction.repayLoan(address(0), 1);
    }

    function testCannotRepayLoanForAccount_paused() public {
        hevm.expectRevert("Pausable: paused");

        lendingAuction.repayLoanForAccount(address(0), 1, uint32(block.timestamp));
    }

    function testCannotPartialRepayLoan_paused() public {
        hevm.expectRevert("Pausable: paused");

        lendingAuction.partialRepayLoan(address(0), 1, 2);
    }

    function testCannotSeizeAsset_paused() public {
        hevm.expectRevert("Pausable: paused");

        lendingAuction.seizeAsset(address(0), 1);
    }
}
