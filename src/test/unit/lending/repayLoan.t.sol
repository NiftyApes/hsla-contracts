// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../utils/fixtures/OffersLoansRefinancesFixtures.sol";

contract TestRepayLoan is Test, OffersLoansRefinancesFixtures {
    function setUp() public override {
        super.setUp();
    }

    function assertionsForExecutedLoan(Offer memory offer) private {
        // borrower has money
        if (offer.asset == address(daiToken)) {
            assertEq(daiToken.balanceOf(borrower1), offer.amount);
        } else {
            assertEq(borrower1.balance, defaultInitialEthBalance + offer.amount);
        }
        // lending contract has NFT
        assertEq(mockNft.ownerOf(1), address(lending));
        // balance increments to one
        assertEq(lending.balanceOf(borrower1, address(mockNft)), 1);
        // nftId exists at index 0
        assertEq(lending.tokenOfOwnerByIndex(borrower1, address(mockNft), 0), 1);
        // loan auction exists
        assertEq(lending.getLoanAuction(address(mockNft), 1).lastUpdatedTimestamp, block.timestamp);
    }

    function assertionsForExecutedERC1155Loan(Offer memory offer) private {
        // borrower has money
        if (offer.asset == address(daiToken)) {
            assertEq(daiToken.balanceOf(borrower1), offer.amount);
        } else {
            assertEq(borrower1.balance, defaultInitialEthBalance + offer.amount);
        }
        // lending contract has the erc1155 nft corresponding to nftId
        assertEq(mockERC1155Token.balanceOf(address(lending), offer.nftId), 1);
        // loan auction exists
        assertEq(lending.getLoanAuction(offer.nftContractAddress, offer.nftId).lastUpdatedTimestamp, block.timestamp);
    }

    function nftOwnershipAssertionsForClosedLoans(address expectedNftOwner) private {
        // expected address has NFT
        assertEq(mockNft.ownerOf(1), expectedNftOwner);
        // balance decrements to 0
        assertEq(lending.balanceOf(borrower1, address(mockNft)), 0);
        // loan auction doesn't exist anymore
        assertEq(lending.getLoanAuction(address(mockNft), 1).lastUpdatedTimestamp, 0);
    }

    function nftOwnershipAssertionsForClosedERC1155Loans(address expectedNftOwner) private {
        // expected address has NFT
        assertEq(mockERC1155Token.balanceOf(expectedNftOwner, 1), 1);
        // balance decrements to 0
        assertEq(lending.balanceOf(borrower1, address(mockERC1155Token)), 0);
        // loan auction doesn't exist anymore
        assertEq(lending.getLoanAuction(address(mockERC1155Token), 1).lastUpdatedTimestamp, 0);
    }

    function _test_repayLoan_simplest_case(
        Offer memory fuzzedOffer,
        uint16 secondsBeforeRepayment
    ) private {
        (Offer memory offer, ) = createOfferAndTryToExecuteLoanByBorrower(
            fuzzedOffer,
            "should work"
        );

        LoanAuction memory loanAuction = lending.getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );

        if (offer.nftContractAddress == address(mockNft)) {
            assertionsForExecutedLoan(offer);
        } else {
            assertionsForExecutedERC1155Loan(offer);
        }
        

        vm.warp(block.timestamp + secondsBeforeRepayment);

        (uint256 accruedLenderInterest, uint256 accruedProtocolInterest) = lending
            .calculateInterestAccrued(
                offer.nftContractAddress,
                offer.nftId
            );

        uint256 interestThreshold = (uint256(loanAuction.amountDrawn) *
            lending.gasGriefingPremiumBps()) / MAX_BPS;

        uint256 interestDelta = 0;

        if (loanAuction.loanEndTimestamp - 1 days > uint32(block.timestamp)) {
            if (interestThreshold > accruedLenderInterest) {
                interestDelta = interestThreshold - accruedLenderInterest;
            }
        }

        uint256 protocolInterest = loanAuction.accumulatedPaidProtocolInterest +
            loanAuction.unpaidProtocolInterest +
            accruedProtocolInterest;

        uint256 interest = (offer.interestRatePerSecond * secondsBeforeRepayment) +
            protocolInterest;

        if (offer.asset == address(daiToken)) {
            // Give borrower enough to pay interest
            mintDai(borrower1, interest + interestDelta);

            uint256 liquidityBalanceBeforeRepay = cDAIToken.balanceOf(address(liquidity));

            vm.startPrank(borrower1);
            daiToken.approve(address(liquidity), ~uint256(0));
            lending.repayLoan(
                offer.nftContractAddress,
                offer.nftId
            );
            vm.stopPrank();

            // Liquidity contract cToken balance
            assertEq(
                cDAIToken.balanceOf(address(liquidity)),
                liquidityBalanceBeforeRepay +
                    liquidity.assetAmountToCAssetAmount(
                        address(daiToken),
                        offer.amount + interest + interestDelta
                    )
            );

            // Borrower back to 0
            assertEq(daiToken.balanceOf(address(borrower1)), 0);

            // Lender back with interest
            assertCloseEnough(
                defaultDaiLiquiditySupplied + interest + interestDelta,
                assetBalance(lender1, address(daiToken)),
                assetBalancePlusOneCToken(lender1, address(daiToken))
            );
        } else {
            uint256 liquidityBalanceBeforeRepay = cEtherToken.balanceOf(address(liquidity));

            vm.startPrank(borrower1);
            vm.expectRevert("00030");
            //  subtract 1 in order to fail when 0 interest
            lending.repayLoan{ value: loanAuction.amountDrawn - 1 }(
                offer.nftContractAddress,
                offer.nftId
            );

            lending.repayLoan{ value: loanAuction.amountDrawn + interest + interestDelta }(
                offer.nftContractAddress,
                offer.nftId
            );
            vm.stopPrank();

            // Liquidity contract cToken balance
            assertEq(
                cEtherToken.balanceOf(address(liquidity)),
                liquidityBalanceBeforeRepay +
                    liquidity.assetAmountToCAssetAmount(
                        address(ETH_ADDRESS),
                        offer.amount + interest + interestDelta
                    )
            );

            // Borrower back to initial minus interest
            assertEq(
                address(borrower1).balance,
                defaultInitialEthBalance - (interest + interestDelta)
            );

            // Lender back with interest
            assertCloseEnough(
                defaultEthLiquiditySupplied + interest + interestDelta,
                assetBalance(lender1, address(ETH_ADDRESS)),
                assetBalancePlusOneCToken(lender1, address(ETH_ADDRESS))
            );
        }
        if (offer.nftContractAddress == address(mockNft)) {
            nftOwnershipAssertionsForClosedLoans(borrower1);
        } else {
            nftOwnershipAssertionsForClosedERC1155Loans(borrower1);
        }
    }

    function test_fuzz_repayLoan_721_simplest_case(
        FuzzedOfferFields memory fuzzedOffer,
        uint16 secondsBeforeRepayment
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        Offer memory offerToCreate = offerStructFromFields(fuzzedOffer, defaultFixedOfferFields);
        _test_repayLoan_simplest_case(offerToCreate, secondsBeforeRepayment);
    }

    function test_fuzz_repayLoan_1155_simplest_case(
        FuzzedOfferFields memory fuzzedOffer,
        uint16 secondsBeforeRepayment
    ) public validateFuzzedOfferFields(fuzzedOffer) {
        Offer memory offerToCreate = offerStructFromFields(fuzzedOffer, defaultFixedOfferFields);
        offerToCreate.nftContractAddress = address(mockERC1155Token);
        offerToCreate.nftId = 1;
        _test_repayLoan_simplest_case(offerToCreate, secondsBeforeRepayment);
    }
}
