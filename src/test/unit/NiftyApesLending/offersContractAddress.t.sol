// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../Offers.sol";
import "../../../Lending.sol";
import "../../common/BaseTest.sol";

import "forge-std/Test.sol";

contract TestOffersContractAddress is BaseTest {
    NiftyApesLending private lendingContract;
    NiftyApesOffers private offersContract;

    function setUp() public {
        lendingContract = new NiftyApesLending();
        lendingContract.initialize();

        offersContract = new NiftyApesOffers();
        offersContract.initialize();
        lendingContract.updateOffersContractAddress(address(offersContract));
    }

    function testOffersContractAddress_works() public {
        assertEq(lendingContract.offersContractAddress(), address(offersContract));
    }

    function testOffersContractAddress_after_update() public {
        NiftyApesOffers newOffersContract = new NiftyApesOffers();
        assertTrue(address(offersContract) != address(newOffersContract));

        newOffersContract.initialize();

        assertEq(lendingContract.offersContractAddress(), address(offersContract));
        lendingContract.updateOffersContractAddress(address(newOffersContract));
        assertEq(lendingContract.offersContractAddress(), address(newOffersContract));
    }
}
