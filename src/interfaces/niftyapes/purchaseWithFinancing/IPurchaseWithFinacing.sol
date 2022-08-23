//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "../offers/IOffersStructs.sol";
import "./ISeaport.sol";

interface IPurchaseWithFinancing is IOffersStructs {
    function purchaseWithFinancingOpenSea(
        Offer memory offer,
        ISeaport.BasicOrderParameters calldata order
    ) external payable;
}
