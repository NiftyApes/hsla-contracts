// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import "./ILSSVMPairFactoryLike.sol";

interface ILSSVMPair {
    enum Error {
        OK, // No error
        INVALID_NUMITEMS, // The numItem value is 0
        SPOT_PRICE_OVERFLOW // The updated spot price doesn't fit into 128 bits
    }

    function nft() external pure returns (address _nft);

    function token() external pure returns (address _token);

    function getBuyNFTQuote(uint256 numNFTs)
        external
        view
        returns (
            Error error,
            uint256 newSpotPrice,
            uint256 newDelta,
            uint256 inputAmount,
            uint256 protocolFee
        );

    function pairVariant()
        external
        pure
        returns (ILSSVMPairFactoryLike.PairVariant);
}