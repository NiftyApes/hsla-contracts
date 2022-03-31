//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title Events emmited for admin changes in the contract.
interface INiftyApesAdminEvents {
    /// @notice Emmited when a new addest and its corresponding asset are added to nifty apes allow list
    /// @param asset The asset being added to the allow list
    /// @param cAsset The address of the corresponding compound token
    event NewAssetListed(address asset, address cAsset);
}
