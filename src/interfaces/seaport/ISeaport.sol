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

    enum OrderType {
        // 0: no partial fills, anyone can execute
        FULL_OPEN,
        // 1: partial fills supported, anyone can execute
        PARTIAL_OPEN,
        // 2: no partial fills, only offerer or zone can execute
        FULL_RESTRICTED,
        // 3: partial fills supported, only offerer or zone can execute
        PARTIAL_RESTRICTED
    }

    enum ItemType {
        // 0: ETH on mainnet, MATIC on polygon, etc.
        NATIVE,
        // 1: ERC20 items (ERC777 and ERC20 analogues could also technically work)
        ERC20,
        // 2: ERC721 items
        ERC721,
        // 3: ERC1155 items
        ERC1155,
        // 4: ERC721 items where a number of tokenIds are supported
        ERC721_WITH_CRITERIA,
        // 5: ERC1155 items where a number of ids are supported
        ERC1155_WITH_CRITERIA
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
        address offerer;
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

    /**
     * @dev An offer item has five components: an item type (ETH or other native
     *      tokens, ERC20, ERC721, and ERC1155, as well as criteria-based ERC721 and
     *      ERC1155), a token address, a dual-purpose "identifierOrCriteria"
     *      component that will either represent a tokenId or a merkle root
     *      depending on the item type, and a start and end amount that support
     *      increasing or decreasing amounts over the duration of the respective
     *      order.
     */
    struct OfferItem {
        ItemType itemType;
        address token;
        uint256 identifierOrCriteria;
        uint256 startAmount;
        uint256 endAmount;
    }

    /**
     * @dev A consideration item has the same five components as an offer item and
     *      an additional sixth component designating the required recipient of the
     *      item.
     */
    struct ConsiderationItem {
        ItemType itemType;
        address token;
        uint256 identifierOrCriteria;
        uint256 startAmount;
        uint256 endAmount;
        address payable recipient;
    }

    /**
     * @notice Retrieve the current counter for a given offerer.
     *
     * @param offerer The offerer in question.
     *
     * @return counter The current counter.
     */
    function getCounter(address offerer)
    external
    view
    returns (uint256 counter);


    /**
 * @dev An order contains eleven components: an offerer, a zone (or account that
 *      can cancel the order or restrict who can fulfill the order depending on
 *      the type), the order type (specifying partial fill support as well as
 *      restricted order status), the start and end time, a hash that will be
 *      provided to the zone when validating restricted orders, a salt, a key
 *      corresponding to a given conduit, a counter, and an arbitrary number of
 *      offer items that can be spent along with consideration items that must
 *      be received by their respective recipient.
 */
    struct OrderComponents {
        address offerer;
        address zone;
        OfferItem[] offer;
        ConsiderationItem[] consideration;
        OrderType orderType;
        uint256 startTime;
        uint256 endTime;
        bytes32 zoneHash;
        uint256 salt;
        bytes32 conduitKey;
        uint256 counter;
    }

    /**
     * @notice Retrieve the order hash for a given order.
     *
     * @param order The components of the order.
     *
     * @return orderHash The order hash.
     */
    function getOrderHash(OrderComponents calldata order)
    external
    view
    returns (bytes32 orderHash);

    /**
     * @dev The full set of order components, with the exception of the counter,
     *      must be supplied when fulfilling more sophisticated orders or groups of
     *      orders. The total number of original consideration items must also be
     *      supplied, as the caller may specify additional consideration items.
     */
    struct OrderParameters {
        address offerer; // 0x00
        address zone; // 0x20
        OfferItem[] offer; // 0x40
        ConsiderationItem[] consideration; // 0x60
        OrderType orderType; // 0x80
        uint256 startTime; // 0xa0
        uint256 endTime; // 0xc0
        bytes32 zoneHash; // 0xe0
        uint256 salt; // 0x100
        bytes32 conduitKey; // 0x120
        uint256 totalOriginalConsiderationItems; // 0x140
        // offer.length                          // 0x160
    }

    /**
     * @dev Orders require a signature in addition to the other order parameters.
     */
    struct Order {
        OrderParameters parameters;
        bytes signature;
    }

    /// @dev taken from https://docs.opensea.io/v2.0/reference/seaport-interface
    function fulfillBasicOrder(BasicOrderParameters calldata parameters)
        external
        payable
        returns (bool fulfilled);

    function fulfillOrder(Order calldata order, bytes32 fulfillerConduitKey)
        external
        payable
        returns (bool fulfilled);
}
