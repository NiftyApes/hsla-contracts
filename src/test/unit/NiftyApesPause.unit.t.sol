// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../../interfaces/compound/ICERC20.sol";
import "../../interfaces/compound/ICEther.sol";
import "../../Lending.sol";
import "../../Offers.sol";
import "../../interfaces/niftyapes/lending/ILendingStructs.sol";
import "../../interfaces/niftyapes/offers/IOffersStructs.sol";

import "../common/BaseTest.sol";
import "../mock/CERC20Mock.sol";
import "../mock/CEtherMock.sol";
import "../mock/ERC20Mock.sol";
import "../mock/ERC721Mock.sol";

contract NiftyApesPauseUnitTest is BaseTest, ILendingStructs, IOffersStructs, ERC721HolderUpgradeable {
    NiftyApesLending niftyApes;
    NiftyApesOffers offersContract;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    CEtherMock cEtherToken;

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
        niftyApes = new NiftyApes();
        niftyApes.initialize();

        offersContract = new NiftyApesOffers();
        offersContract.initialize();

        offersContract.updateLendingContractAddress(address(niftyApes));

        usdcToken = new ERC20Mock();
        usdcToken.initialize("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock();
        cUSDCToken.initialize(usdcToken);
        niftyApes.setCAssetAddress(address(usdcToken), address(cUSDCToken));

        cEtherToken = new CEtherMock();
        cEtherToken.initialize();
        niftyApes.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        niftyApes.pause();

        acceptEth = true;

        mockNft = new ERC721Mock();
        mockNft.initialize("BoredApe", "BAYC");

        mockNft.safeMint(address(this), 1);
        mockNft.approve(address(niftyApes), 1);

        mockNft.safeMint(address(this), 2);
        mockNft.approve(address(niftyApes), 2);
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
                asset: address(usdcToken),
                amount: 6,
                duration: 7,
                expiration: 8
            });
    }

    function testCannotPause_not_owner() public {
        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Ownable: caller is not the owner");

        niftyApes.pause();
    }

    function testCannotUnpause_not_owner() public {
        hevm.startPrank(LENDER_1);

        hevm.expectRevert("Ownable: caller is not the owner");

        niftyApes.unpause();
    }

    function testCannotsupplyErc20_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.supplyErc20(address(usdcToken), 1);
    }

    function testCannotSupplyErc20_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.supplyErc20(address(usdcToken), 1);
    }

    function testCannotSupplyCErc20_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.supplyCErc20(address(cUSDCToken), 1);
    }

    function testCannotWithdrawErc20_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.withdrawErc20(address(usdcToken), 1);
    }

    function testCannotwithdrawCErc20_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.withdrawCErc20(address(cUSDCToken), 1);
    }

    function testCannotSupplyEth_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.supplyEth();
    }

    function testCannotWithdrawEth_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.withdrawEth(1);
    }

    function testCannotExecuteLoanByBorrower_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.executeLoanByBorrower(address(offersContract), address(0), 1, bytes32(0), false);
    }

    function testCannotExecuteLoanByBorrowerSignature_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.executeLoanByBorrowerSignature(address(offersContract), getOffer(), "", 0);
    }

    function testCannotExecuteLoanByLender_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.executeLoanByLender(address(offersContract), address(0), 1, bytes32(0), false);
    }

    function testCannotExecuteLoanByLenderSignature_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.executeLoanByLenderSignature(address(offersContract), getOffer(), "");
    }

    function testCannotRefinanceByBorrower_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.refinanceByBorrower(address(offersContract), address(0), 1, false, bytes32(0));
    }

    function testCannotRefinanceByBorrowerSignature_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.refinanceByBorrowerSignature(address(offersContract), getOffer(), "", 1);
    }

    function testCannotRefinanceByLender_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.refinanceByLender(getOffer());
    }

    function testCannotDrawLoanAmount_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.drawLoanAmount(address(0), 1, 2);
    }

    function testCannotRepayLoan_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.repayLoan(address(0), 1);
    }

    function testCannotRepayLoanForAccount_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.repayLoanForAccount(address(0), 1);
    }

    function testCannotPartialRepayLoan_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.partialRepayLoan(address(0), 1, 2);
    }

    function testCannotSeizeAsset_paused() public {
        hevm.expectRevert("Pausable: paused");

        niftyApes.seizeAsset(address(0), 1);
    }
}
