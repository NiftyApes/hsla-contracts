// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./Console.sol";
import "ds-test/test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/compound/ICERC20.sol";
import "../interfaces/compound/ICEther.sol";
import "../LendingAuction.sol";
import "../interfaces/ILendingAuctionEvents.sol";
import "../Exponential.sol";
import "./Utilities.sol";

import "./mock/CERC20Mock.sol";
import "./mock/CEtherMock.sol";
import "./mock/ERC20Mock.sol";

contract LendingAuctionUnitTest is
    DSTest,
    TestUtility,
    Exponential,
    ILendingAuctionEvents,
    ILendingAuctionStructs
{
    LendingAuction lendingAction;
    ERC20Mock usdcToken;
    CERC20Mock cUSDCToken;

    CEtherMock cEtherToken;

    bool acceptEth;

    address constant ZERO_ADDRESS = address(0);

    receive() external payable {
        require(acceptEth, "acceptEth");
    }

    function setUp() public {
        lendingAction = new LendingAuction();

        usdcToken = new ERC20Mock("USD Coin", "USDC");
        cUSDCToken = new CERC20Mock(usdcToken);
        lendingAction.setCAssetAddress(address(usdcToken), address(cUSDCToken));

        cEtherToken = new CEtherMock();
        lendingAction.setCAssetAddress(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(cEtherToken)
        );

        acceptEth = true;
    }

    function testGetLoanAction_returns_empty_loan_auction() public {
        LoanAuction memory loanAuction = lendingAction.getLoanAuction(
            address(0x0000000000000000000000000000000000000001),
            2
        );

        assertEq(loanAuction.nftOwner, ZERO_ADDRESS);
        assertEq(loanAuction.lender, ZERO_ADDRESS);
        assertEq(loanAuction.asset, ZERO_ADDRESS);
        assertEq(loanAuction.interestRateBps, 0);
        assertTrue(!loanAuction.fixedTerms);

        assertEq(loanAuction.amount, 0);
        assertEq(loanAuction.duration, 0);
        assertEq(loanAuction.loanExecutedTime, 0);
        assertEq(loanAuction.timeOfInterestStart, 0);
        assertEq(loanAuction.historicLenderInterest, 0);
        assertEq(loanAuction.historicProtocolInterest, 0);
        assertEq(loanAuction.amountDrawn, 0);
        assertEq(loanAuction.timeDrawn, 0);
    }
}
