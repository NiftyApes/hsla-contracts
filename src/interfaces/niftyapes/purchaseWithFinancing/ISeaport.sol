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
        address considerationToken;
        uint256 considerationIdentifier;
        uint256 considerationAmount;
        address payable offerer;
        address zone;
        address offerToken;
        uint256 offerIdentifier;
        uint256 offerAmount;
        BasicOrderType basicOrderType;
        uint256 startTime;
        uint256 endTime;
        bytes32 zoneHash;
        uint256 salt;
        bytes32 offererConduitKey;
        bytes32 fulfillerConduitKey;
        uint256 totalOriginalAdditionalRecipients;
        AdditionalRecipient[] additionalRecipients;
        bytes signature;
    }

    /// @dev taken from https://docs.opensea.io/v2.0/reference/seaport-interface
    function fulfillBasicOrder(BasicOrderParameters calldata parameters)
        external
        payable
        returns (bool fulfilled);
}
