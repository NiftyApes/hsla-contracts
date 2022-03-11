//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../../lib/LibOrder.sol";

interface IExchangeV2Core {
    function matchOrders(
        LibOrder.Order memory orderLeft,
        bytes memory signatureLeft,
        LibOrder.Order memory orderRight,
        bytes memory signatureRight
    ) external payable;
}
