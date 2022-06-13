// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../SigLending.sol";
import "../../../Lending.sol";
import "../../common/BaseTest.sol";

import "forge-std/Test.sol";

contract TestUpdateSigLendingContractAddress is BaseTest, Test {
    NiftyApesLending private lendingContract;
    NiftyApesSigLending private sigLendingContract;

    // Below are two random addresses
    address private constant EOA_1 = 0x503408564C50b43208529faEf9bdf9794c015d52;
    address private constant EOA_2 = 0x4a3A70D6Be2290f5F57Ac7E64b9A1B7695f5b0B3;

    function setUp() public {
        vm.startPrank(EOA_1);

        lendingContract = new NiftyApesLending();
        lendingContract.initialize();
        sigLendingContract = new NiftyApesSigLending();
        sigLendingContract.initialize();
        lendingContract.updateSigLendingContractAddress(address(sigLendingContract));

        vm.stopPrank();
    }

    function testUpdateSigLendingContractAddress_works() public {
        NiftyApesSigLending newSigLendingContract = new NiftyApesSigLending();
        newSigLendingContract.initialize();

        vm.prank(EOA_1);
        lendingContract.updateSigLendingContractAddress(address(newSigLendingContract));

        assertEq(lendingContract.sigLendingContractAddress(), address(newSigLendingContract));
    }

    function testUpdateSigLendingContractAddress_works_after_transfer() public {
        NiftyApesSigLending newSigLendingContract = new NiftyApesSigLending();
        newSigLendingContract.initialize();

        vm.prank(EOA_2);
        vm.expectRevert("Ownable: caller is not the owner");
        lendingContract.updateSigLendingContractAddress(address(newSigLendingContract));
        vm.stopPrank();

        assertEq(lendingContract.sigLendingContractAddress(), address(sigLendingContract));

        vm.startPrank(EOA_1);
        lendingContract.transferOwnership(EOA_2);
        vm.stopPrank();

        vm.prank(EOA_2);
        lendingContract.updateSigLendingContractAddress(address(newSigLendingContract));
        vm.stopPrank();

        assertEq(lendingContract.sigLendingContractAddress(), address(newSigLendingContract));
    }

    function testCannotUpdateSigLendingContractAddress_if_not_owner() public {
        NiftyApesSigLending newSigLendingContract = new NiftyApesSigLending();
        newSigLendingContract.initialize();

        vm.expectRevert("Ownable: caller is not the owner");
        lendingContract.updateSigLendingContractAddress(address(newSigLendingContract));

        assertEq(lendingContract.sigLendingContractAddress(), address(sigLendingContract));
    }

    function testCannotUpdateSigLendingContractAddress_if_not_owner_after_transfer() public {
        NiftyApesSigLending newSigLendingContract = new NiftyApesSigLending();
        newSigLendingContract.initialize();

        vm.startPrank(EOA_1);
        lendingContract.transferOwnership(EOA_2);
        vm.expectRevert("Ownable: caller is not the owner");
        lendingContract.updateSigLendingContractAddress(address(newSigLendingContract));
        vm.stopPrank();

        assertEq(lendingContract.sigLendingContractAddress(), address(sigLendingContract));
    }
}
