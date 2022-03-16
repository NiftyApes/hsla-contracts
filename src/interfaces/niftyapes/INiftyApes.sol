//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./admin/INiftyApesAdmin.sol";
import "./lending/ILending.sol";
import "./liquidity/ILiquidity.sol";

/// @title NiftyApes main interface
interface INiftyApes is INiftyApesAdmin, ILending, ILiquidity {

}
