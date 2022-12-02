// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import "./ILSSVMPair.sol";

interface ILSSVMPairFactoryLike {
    enum PairVariant {
        ENUMERABLE_ETH,
        MISSING_ENUMERABLE_ETH,
        ENUMERABLE_ERC20,
        MISSING_ENUMERABLE_ERC20
    }

    enum PoolType {
        TOKEN,
        NFT,
        TRADE
    }

    /**
        @notice Creates a pair contract using EIP-1167.
        @param _nft The NFT contract of the collection the pair trades
        @param _bondingCurve The bonding curve for the pair to price NFTs, must be whitelisted
        @param _assetRecipient The address that will receive the assets traders give during trades.
                                If set to address(0), assets will be sent to the pool address.
                                Not available to TRADE pools.
        @param _poolType TOKEN, NFT, or TRADE
        @param _delta The delta value used by the bonding curve. The meaning of delta depends
        on the specific curve.
        @param _fee The fee taken by the LP in each trade. Can only be non-zero if _poolType is Trade.
        @param _spotPrice The initial selling spot price, in ETH
        @param _initialNFTIDs The list of IDs of NFTs to transfer from the sender to the pair
        @param _initialTokenBalance The initial token balance sent from the sender to the new pair
        @return pair The new pair
     */
    struct CreateERC20PairParams {
        address token;
        address nft;
        address bondingCurve;
        address payable assetRecipient;
        PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        uint256[] initialNFTIDs;
        uint256 initialTokenBalance;
    }

    function createPairERC20(CreateERC20PairParams calldata params)
        external
        returns (ILSSVMPair pair);

    /**
        @notice Creates a pair contract using EIP-1167.
        @param nft The NFT contract of the collection the pair trades
        @param bondingCurve The bonding curve for the pair to price NFTs, must be whitelisted
        @param assetRecipient The address that will receive the assets traders give during trades.
                              If set to address(0), assets will be sent to the pool address.
                              Not available to TRADE pools. 
        @param poolType TOKEN, NFT, or TRADE
        @param delta The delta value used by the bonding curve. The meaning of delta depends
        on the specific curve.
        @param fee The fee taken by the LP in each trade. Can only be non-zero if _poolType is Trade.
        @param spotPrice The initial selling spot price
        @param initialNFTIDs The list of IDs of NFTs to transfer from the sender to the pair
        @return pair The new pair
     */
    function createPairETH(
        address nft,
        address bondingCurve,
        address payable assetRecipient,
        PoolType poolType,
        uint128 delta,
        uint96 fee,
        uint128 spotPrice,
        uint256[] calldata initialNFTIDs
    ) external payable returns (ILSSVMPair pair);

    function isPair(address potentialPair, PairVariant variant)
        external
        view
        returns (bool);

    function protocolFeeMultiplier() external view returns (uint256);
}