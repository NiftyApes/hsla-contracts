pragma solidity 0.8.13;

import "../offers/IOffersStructs.sol";

interface IPurchaseWithFinancing is IOffersStructs {
    function purchaseWithFinancingOpenSea(Offer memory offer, BasicOrderParameters calldata order)
        external
        payable;
}
