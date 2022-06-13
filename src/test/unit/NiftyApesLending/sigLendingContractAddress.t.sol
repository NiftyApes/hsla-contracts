// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../Lending.sol";
import "../../../SigLending.sol";
import "../../common/BaseTest.sol";

import "forge-std/Test.sol";

contract TestSigLendingContractAddress is BaseTest {
    NiftyApesLending private lendingContract;
    NiftyApesSigLending private sigLendingContract;

    function setUp() public {
        lendingContract = new NiftyApesLending();
        lendingContract.initialize();

        sigLendingContract = new NiftyApesSigLending();
        sigLendingContract.initialize();
        lendingContract.updateSigLendingContractAddress(address(sigLendingContract));
    }

    function testSigLendingContractAddress() public {
        assertEq(lendingContract.sigLendingContractAddress(), address(sigLendingContract));
    }

    function testSigLendingContractAddress_after_update() public {
        NiftyApesSigLending newSigLendingContract = new NiftyApesSigLending();
        assertTrue(address(sigLendingContract) != address(newSigLendingContract));

        newSigLendingContract.initialize();

        assertEq(lendingContract.sigLendingContractAddress(), address(sigLendingContract));
        lendingContract.updateSigLendingContractAddress(address(newSigLendingContract));
        assertEq(lendingContract.sigLendingContractAddress(), address(newSigLendingContract));
    }
}
