// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.11;

import "ds-test/test.sol";
import "./Hevm.sol";

contract BaseUnitTest is DSTest {
    Hevm public hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
}
