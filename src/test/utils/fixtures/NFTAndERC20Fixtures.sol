pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/StringsUpgradeable.sol";
import "forge-std/Test.sol";

import "./UsersFixtures.sol";

import "../../mock/ERC20Mock.sol";
import "../../mock/CERC20Mock.sol";
import "../../mock/ERC721Mock.sol";
import "../../mock/CEtherMock.sol";

import "forge-std/Test.sol";

// mints NFTs to borrowers
// supplies DAI to lenders
contract NFTAndERC20Fixtures is Test, UsersFixtures {
    ERC20Mock internal daiToken;
    ERC20Mock internal compToken;
    CERC20Mock internal cDAIToken;
    CEtherMock internal cEtherToken;
    ERC721Mock internal mockNft;

    bool internal integration = false;

    // need to replace dai whales with DAI whales
    address constant daiWhale1 = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
    address constant daiWhale2 = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;
    address constant daiWhale = 0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf;

    address constant compWhale = 0x2775b1c75658Be0F640272CCb8c72ac986009e38;

    function setUp() public virtual override {
        super.setUp();

        try vm.envBool("INTEGRATION") returns (bool isIntegration) {
            integration = isIntegration;
        } catch (bytes memory) {
            // This catches revert that occurs if env variable not supplied
        }

        // need to replace DAI contracts with DAI
        if (integration) {
            daiToken = ERC20Mock(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

            compToken = ERC20Mock(0xc00e94Cb662C3520282E6f5717214004A7f26888);

            cDAIToken = CERC20Mock(0x39AA39c021dfbaE8faC545936693aC917d5E7563);

            cEtherToken = CEtherMock(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);

            uint256 daiWhale1Balance = daiToken.balanceOf(daiWhale1);
            uint256 daiWhale2Balance = daiToken.balanceOf(daiWhale2);

            vm.startPrank(daiWhale1);
            daiToken.transfer(lender1, daiWhale1Balance);
            vm.stopPrank();
            vm.startPrank(daiWhale2);
            daiToken.transfer(lender2, daiWhale2Balance);
            vm.stopPrank();
        } else {
            daiToken = new ERC20Mock();
            daiToken.initialize("USD Coin", "DAI");

            compToken = new ERC20Mock();
            compToken.initialize("Compound", "COMP");

            cDAIToken = new CERC20Mock();
            cDAIToken.initialize(daiToken);

            cEtherToken = new CEtherMock();
            cEtherToken.initialize();

            daiToken.mint(lender1, 3672711471 ether);
            daiToken.mint(lender2, 3672711471 ether);
            daiToken.mint(SANCTIONED_ADDRESS, 3672711471 ether);
        }

        mockNft = new ERC721Mock();
        mockNft.initialize("BoredApe", "BAYC");

        mockNft.safeMint(address(borrower1), 1);
        mockNft.safeMint(address(borrower2), 2);
        mockNft.safeMint(SANCTIONED_ADDRESS, 3);
    }

    function mintUsdc(address recipient, uint256 amount) internal {
        if (integration) {
            vm.startPrank(daiWhale);
            daiToken.transfer(recipient, amount);
            vm.stopPrank();
        } else {
            daiToken.mint(recipient, amount);
        }
    }

    function assertBetween(
        uint256 value,
        uint256 lowerBound,
        uint256 upperBound
    ) internal view {
        if (value > upperBound) {
            console.log("***assertBetween log***");
            console.log("value", value);
            console.log("upperBound", upperBound);
            revert("assertBetween: value greater than upper bound");
        }

        if (value < lowerBound) {
            console.log("***assertBetween log***");
            console.log("value", value);
            console.log("lowerBound", lowerBound);
            revert("assertBetween: value less than lower bound");
        }
    }

    function isApproxEqual(
        uint256 expected,
        uint256 actual,
        uint256 tolerance
    ) public pure returns (bool) {
        uint256 leftBound = (expected * (1000 - tolerance)) / 1000;
        uint256 rightBound = (expected * (1000 + tolerance)) / 1000;
        return (leftBound <= actual && actual <= rightBound);
    }

    function assertCloseEnough(
        uint256 value,
        uint256 lowerBound,
        uint256 upperBound
    ) internal view {
        if (isApproxEqual(value, lowerBound, 1)) {
            // all good
        } else {
            assertBetween(value, lowerBound, upperBound);
        }
    }
}
