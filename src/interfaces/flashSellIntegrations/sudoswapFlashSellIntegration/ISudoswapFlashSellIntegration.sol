//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ISudoswapFlashSellIntegrationAdmin.sol";
import "./ISudoswapFlashSellIntegrationEvents.sol";
import "../../niftyapes/offers/IOffersStructs.sol";
import "../../sudoswap/ILSSVMPair.sol";

interface ISudoswapFlashSellIntegration is
    ISudoswapFlashSellIntegrationAdmin,
    ISudoswapFlashSellIntegrationEvents,
    IOffersStructs
{
    /// @notice Returns the address for the associated FlashSell contract
    function flashSellContractAddress() external view returns (address);

    /// @notice Returns the address for the associated sudoswap router
    function sudoswapRouterContractAddress() external view returns (address);

    /// @notice Returns the address for the associated sudoswap factory
    function sudoswapFactoryContractAddress() external view returns (address);
}
