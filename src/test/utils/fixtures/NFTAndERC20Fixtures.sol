// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/StringsUpgradeable.sol";
import "forge-std/Test.sol";

import "./UsersFixtures.sol";

import "../../mock/ERC20Mock.sol";
import "../../mock/CERC20Mock.sol";
import "../../mock/ERC721Mock.sol";
import "../../mock/CEtherMock.sol";

// mints NFTs to borrowers
// supplies USDC to lenders
contract NFTAndERC20Fixtures is Test, UsersFixtures {
    ERC20Mock internal usdcToken;
    CERC20Mock internal cUSDCToken;
    CEtherMock internal cEtherToken;
    ERC721Mock internal mockNft;

    function setUp() public virtual override {
        super.setUp();

        usdcToken = new ERC20Mock();
        usdcToken.initialize("USD Coin", "USDC");

        cUSDCToken = new CERC20Mock();
        cUSDCToken.initialize(usdcToken);

        cEtherToken = new CEtherMock();
        cEtherToken.initialize();

        usdcToken.mint(lender1, 1000 ether);
        usdcToken.mint(lender2, 1000 ether);

        mockNft = new ERC721Mock();
        mockNft.initialize("BoredApe", "BAYC");

        mockNft.safeMint(address(borrower1), 1);
        mockNft.safeMint(address(borrower2), 2);
    }
}
