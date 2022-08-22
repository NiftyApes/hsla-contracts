//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

interface ISeaport {
    /// @dev Taken from https://docs.opensea.io/v2.0/reference/seaport-enums
    /// And removed all enums without the prefix `ETH_TO_`
    enum BasicOrderType {
        ETH_TO_ERC721_FULL_OPEN,
        ETH_TO_ERC721_PARTIAL_OPEN,
        ETH_TO_ERC721_FULL_RESTRICTED,
        ETH_TO_ERC721_PARTIAL_RESTRICTED,
        ETH_TO_ERC1155_FULL_OPEN,
        ETH_TO_ERC1155_PARTIAL_OPEN,
        ETH_TO_ERC1155_FULL_RESTRICTED,
        ETH_TO_ERC1155_PARTIAL_RESTRICTED
    }

    /// @dev taken from https://docs.opensea.io/v2.0/reference/seaport-structs
    struct AdditionalRecipient {
        uint256 amount;
        address payable recipient;
    }

    /// @dev taken from https://docs.opensea.io/v2.0/reference/seaport-structs
    struct BasicOrderParameters {
        // calldata offset
        address considerationToken; // 0x24
        uint256 considerationIdentifier; // 0x44
        uint256 considerationAmount; // 0x64
        address payable offerer; // 0x84
        address zone; // 0xa4
        address offerToken; // 0xc4
        uint256 offerIdentifier; // 0xe4
        uint256 offerAmount; // 0x104
        BasicOrderType basicOrderType; // 0x124
        uint256 startTime; // 0x144
        uint256 endTime; // 0x164
        bytes32 zoneHash; // 0x184
        uint256 salt; // 0x1a4
        bytes32 offererConduitKey; // 0x1c4
        bytes32 fulfillerConduitKey; // 0x1e4
        uint256 totalOriginalAdditionalRecipients; // 0x204
        AdditionalRecipient[] additionalRecipients; // 0x224
        bytes signature; // 0x244
        // Total length, excluding dynamic array data: 0x264 (580)
    }

    /// @dev taken from https://docs.opensea.io/v2.0/reference/seaport-interface
    function fulfillBasicOrder(BasicOrderParameters calldata parameters)
        external
        payable
        returns (bool fulfilled);
}
