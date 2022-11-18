//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ISeaportFlashSellIntegrationAdmin.sol";
import "./ISeaportFlashSellIntegrationEvents.sol";
import "../../seaport/ISeaport.sol";

interface ISeaportFlashSellIntegration is
    ISeaportFlashSellIntegrationAdmin,
    ISeaportFlashSellIntegrationEvents
{
    /// @notice Returns the address for the associated flashSell contract
    function flashSellContractAddress() external view returns (address);

    /// @notice Returns the address for the weth contract
    function wethContractAddress() external view returns (address);

    /// @notice Returns the address for the seaport contract
    function seaportContractAddress() external view returns (address);

  
}
