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
// supplies USDC to lenders
contract NFTAndERC20Fixtures is Test, UsersFixtures {
    ERC20Mock internal usdcToken;
    ERC20Mock internal compToken;
    CERC20Mock internal cUSDCToken;
    CEtherMock internal cEtherToken;
    ERC721Mock internal mockNft;

    bool internal integration = false;

    address constant usdcWhale = 0x68A99f89E475a078645f4BAC491360aFe255Dff1;
    address constant compWhale = 0x2775b1c75658Be0F640272CCb8c72ac986009e38;

    function setUp() public virtual override {
        super.setUp();

        try vm.envBool("INTEGRATION") returns (bool isIntegration) {
            integration = isIntegration;
        } catch (bytes memory) {
            // This catches revert that occurs if env variable not supplied
        }

        if (integration) {
            usdcToken = ERC20Mock(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

            compToken = ERC20Mock(0xc00e94Cb662C3520282E6f5717214004A7f26888);

            cUSDCToken = CERC20Mock(0x39AA39c021dfbaE8faC545936693aC917d5E7563);

            cEtherToken = CEtherMock(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);

            vm.startPrank(usdcWhale);
            usdcToken.transfer(lender1, 2000 * (10**usdcToken.decimals()));
            usdcToken.transfer(lender2, 2000 * (10**usdcToken.decimals()));
            usdcToken.transfer(lender3, 2000 * (10**usdcToken.decimals()));
            vm.stopPrank();
        } else {
            usdcToken = new ERC20Mock();
            usdcToken.initialize("USD Coin", "USDC");

            compToken = new ERC20Mock();
            compToken.initialize("Compound", "COMP");

            cUSDCToken = new CERC20Mock();
            cUSDCToken.initialize(usdcToken);

            cEtherToken = new CEtherMock();
            cEtherToken.initialize();

            usdcToken.mint(lender1, 2000 ether);
            usdcToken.mint(lender2, 2000 ether);
            usdcToken.mint(lender3, 2000 ether);
            usdcToken.mint(SANCTIONED_ADDRESS, 1000 ether);
        }

        mockNft = new ERC721Mock();
        mockNft.initialize("BoredApe", "BAYC");

        mockNft.safeMint(address(borrower1), 1);
        mockNft.safeMint(address(borrower2), 2);
        mockNft.safeMint(SANCTIONED_ADDRESS, 3);
    }

    function mintUsdc(address recipient, uint256 amount) internal {
        if (integration) {
            vm.startPrank(usdcWhale);
            usdcToken.transfer(recipient, amount);
            vm.stopPrank();
        } else {
            usdcToken.mint(recipient, amount);
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
    ) public returns (bool) {
        uint256 leftBound = (expected * (1000 - tolerance)) / 1000;
        uint256 rightBound = (expected * (1000 + tolerance)) / 1000;
        return (leftBound <= actual && actual <= rightBound);
    }

    function assertCloseEnough(
        uint256 value,
        uint256 lowerBound,
        uint256 upperBound
    ) internal {
        if (isApproxEqual(value, lowerBound, 1)) {
            // all good
        } else {
            assertBetween(value, lowerBound, upperBound);
        }
    }
}
