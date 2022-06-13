// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../Offers.sol";
import "../../../Lending.sol";
import "../../common/BaseTest.sol";

import "forge-std/Test.sol";

contract TestUpdateOffersContractAddress is BaseTest, Test {
    NiftyApesLending private lendingContract;
    NiftyApesOffers private offersContract;

    // Below are two random addresses
    address private constant EOA_1 = 0x503408564C50b43208529faEf9bdf9794c015d52;
    address private constant EOA_2 = 0x4a3A70D6Be2290f5F57Ac7E64b9A1B7695f5b0B3;

    function setUp() public {
        vm.startPrank(EOA_1);

        lendingContract = new NiftyApesLending();
        lendingContract.initialize();
        offersContract = new NiftyApesOffers();
        offersContract.initialize();
        lendingContract.updateOffersContractAddress(address(offersContract));

        vm.stopPrank();
    }

    function testUpdateOffersContractAddress_works() public {
        NiftyApesOffers newOffersContract = new NiftyApesOffers();
        newOffersContract.initialize();

        vm.prank(EOA_1);
        lendingContract.updateOffersContractAddress(address(newOffersContract));

        assertEq(lendingContract.offersContractAddress(), address(newOffersContract));
    }

    function testUpdateOffersContractAddress_works_after_transfer() public {
        NiftyApesOffers newOffersContract = new NiftyApesOffers();
        newOffersContract.initialize();

        vm.prank(EOA_2);
        vm.expectRevert("Ownable: caller is not the owner");
        lendingContract.updateOffersContractAddress(address(newOffersContract));
        vm.stopPrank();

        assertEq(lendingContract.offersContractAddress(), address(offersContract));

        vm.startPrank(EOA_1);
        lendingContract.transferOwnership(EOA_2);
        vm.stopPrank();

        vm.prank(EOA_2);
        lendingContract.updateOffersContractAddress(address(newOffersContract));
        vm.stopPrank();

        assertEq(lendingContract.offersContractAddress(), address(newOffersContract));
    }

    function testCannotUpdateOffersContractAddress_if_not_owner() public {
        NiftyApesOffers newOffersContract = new NiftyApesOffers();
        newOffersContract.initialize();

        vm.expectRevert("Ownable: caller is not the owner");
        lendingContract.updateOffersContractAddress(address(newOffersContract));

        assertEq(lendingContract.offersContractAddress(), address(offersContract));
    }

    function testCannotUpdateOffersContractAddress_if_not_owner_after_transfer() public {
        NiftyApesOffers newOffersContract = new NiftyApesOffers();
        newOffersContract.initialize();

        vm.startPrank(EOA_1);
        lendingContract.transferOwnership(EOA_2);
        vm.expectRevert("Ownable: caller is not the owner");
        lendingContract.updateOffersContractAddress(address(newOffersContract));
        vm.stopPrank();

        assertEq(lendingContract.offersContractAddress(), address(offersContract));
    }
}
