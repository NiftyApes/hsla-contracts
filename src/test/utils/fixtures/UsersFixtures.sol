// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/StringsUpgradeable.sol";
import "forge-std/Test.sol";

// creates payable addresses
// borrower1, borrower2, lender1, lender2, owner
// and a users array with 10 users
// the balance of each payable address is set to 1000 eth
// and vm.label is used to add clarity to stack traces
contract UsersFixtures is Test {
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    address payable internal borrower1;
    address payable internal borrower2;
    address payable internal lender1;
    address payable internal lender2;
    address payable internal owner;

    address payable[10] internal users;

    function setUp() public virtual {
        borrower1 = getNextUserAddress();
        vm.deal(borrower1, 1000 ether);
        vm.label(borrower1, "borrower1");

        borrower2 = getNextUserAddress();
        vm.deal(borrower2, 1000 ether);
        vm.label(borrower2, "borrower2");

        lender1 = getNextUserAddress();
        vm.deal(lender1, 1000 ether);
        vm.label(lender1, "lender1");

        lender2 = getNextUserAddress();
        vm.deal(lender2, 1000 ether);
        vm.label(lender2, "lender2");

        owner = getNextUserAddress();
        vm.deal(owner, 1000 ether);
        vm.label(owner, "owner");

        for (uint256 i = 0; i < 10; i++) {
            address payable user = getNextUserAddress();
            vm.deal(user, 1000 ether);
            users[i] = user;
            vm.label(user, string.concat("user", StringsUpgradeable.toString(i)));
        }
    }

    function getNextUserAddress() internal returns (address payable) {
        // bytes32 to address conversion
        // bytes32 (32 bytes) => uint256 (32 bytes) => uint160 (20 bytes) => address (20 bytes)
        // explicit type conversion not allowed from "bytes32" to "uint160"
        // nor from "uint256" to "address"
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }
}
