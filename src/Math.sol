//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.11;

library Math {
    uint256 constant expScale = 1e18;

    // See compound Exponential#divScalarByExpTruncate
    function divScalarByExpTruncate(uint256 scalar, uint256 exponent)
        internal
        pure
        returns (uint256)
    {
        uint256 numerator = scalar * expScale;
        uint256 scaledNumerator = numerator * expScale;
        uint256 fraction = scaledNumerator / exponent;
        return fraction / expScale;
    }
}
