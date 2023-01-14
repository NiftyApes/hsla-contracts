//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165CheckerUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "./interfaces/erc1155/IERC1155SupplyUpgradeable.sol";
import "./interfaces/niftyapes/offers/IOffers.sol";
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./lib/ECDSABridge.sol";

/// @title NiftyApes Offers
/// @custom:version 1.0
/// @author captnseagraves (captnseagraves.eth)
/// @custom:contributor dankurka
/// @custom:contributor 0xAlcibiades (alcibiades.eth)
/// @custom:contributor zjmiller (zjmiller.eth)

contract NiftyApesOffers is OwnableUpgradeable, PausableUpgradeable, EIP712Upgradeable, IOffers {
    using ERC165CheckerUpgradeable for address;

    /// @dev empty slot for v1.0 offer book
    mapping(address => mapping(uint256 => mapping(bytes32 => Offer))) private _prevNftOfferBooks;

    /// @dev empty slot for v1.0 floor offer book
    mapping(address => mapping(bytes32 => Offer)) private _prevFloorOfferBooks;

    /// @dev A mapping for an on chain offerHash to a floor offer counter
    mapping(bytes32 => uint64) private _floorOfferCounters;

    /// @dev A mapping for a signautre offer to a floor offer counter
    mapping(bytes => uint64) private _sigFloorOfferCounters;

    /// @dev A mapping to mark a signature as used.
    ///      The mapping allows users to withdraw offers that they made by signature.
    mapping(bytes => bool) private _cancelledOrFinalized;

    /// @inheritdoc IOffers
    address public lendingContractAddress;

    /// @inheritdoc IOffers
    address public sigLendingContractAddress;

    /// @inheritdoc IOffers
    address public liquidityContractAddress;

    /// @dev Constant typeHash for EIP-712 hashing of Offer struct
    ///      If the Offer struct shape changes, this will need to change as well.
    bytes32 private constant _OFFER_TYPEHASH =
        keccak256(
            "Offer(address creator,uint32 duration,uint32 expiration,bool fixedTerms,bool floorTerm,bool lenderOffer,address nftContractAddress,uint256 nftId,address asset,uint128 amount,uint96 interestRatePerSecond,uint64 floorTermLimit)"
        );

    /// @inheritdoc IOffers
    address public flashPurchaseContractAddress;

    /// @inheritdoc IOffers
    address public refinanceContractAddress;

    /// @dev A mapping for storing offers with offerHash as their keys
    mapping(bytes32 => Offer) private _nftOfferBooks;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[496] private __gap;

    /// @notice The initializer for the NiftyApes protocol.
    ///         NiftyApes is intended to be deployed behind a proxy and thus needs to initialize
    ///         its state outside of a constructor.
    function initialize(
        address newliquidityContractAddress,
        address newRefinanceContractAddress,
        address newFlashPurchaseContractAddress
    ) public initializer {
        EIP712Upgradeable.__EIP712_init("NiftyApes_Offers", "0.0.1");

        liquidityContractAddress = newliquidityContractAddress;
        refinanceContractAddress = newRefinanceContractAddress;
        flashPurchaseContractAddress = newFlashPurchaseContractAddress;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
    }

    /// @inheritdoc IOffersAdmin
    function updateLendingContractAddress(address newLendingContractAddress) external onlyOwner {
        require(address(newLendingContractAddress) != address(0), "00035");
        emit OffersXLendingContractAddressUpdated(
            lendingContractAddress,
            newLendingContractAddress
        );
        lendingContractAddress = newLendingContractAddress;
    }

    /// @inheritdoc IOffersAdmin
    function updateSigLendingContractAddress(address newSigLendingContractAddress)
        external
        onlyOwner
    {
        require(address(newSigLendingContractAddress) != address(0), "00035");
        emit OffersXSigLendingContractAddressUpdated(
            sigLendingContractAddress,
            newSigLendingContractAddress
        );
        sigLendingContractAddress = newSigLendingContractAddress;
    }

    /// @inheritdoc IOffersAdmin
    function updateRefinanceContractAddress(address newRefinanceContractAddress)
        external
        onlyOwner
    {
        require(address(newRefinanceContractAddress) != address(0), "00035");
        emit OffersXRefinanceContractAddressUpdated(
            refinanceContractAddress,
            newRefinanceContractAddress
        );
        refinanceContractAddress = newRefinanceContractAddress;
    }

    /// @inheritdoc IOffersAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IOffersAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IOffers
    function getOfferHash(Offer memory offer) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _OFFER_TYPEHASH,
                        offer.creator,
                        offer.duration,
                        offer.expiration,
                        offer.fixedTerms,
                        offer.floorTerm,
                        offer.lenderOffer,
                        offer.nftContractAddress,
                        offer.nftId,
                        offer.asset,
                        offer.amount,
                        offer.interestRatePerSecond,
                        offer.floorTermLimit
                    )
                )
            );
    }

    /// @inheritdoc IOffers
    function getOfferSigner(Offer memory offer, bytes memory signature)
        public
        view
        override
        returns (address)
    {
        return ECDSABridge.recover(getOfferHash(offer), signature);
    }

    /// @inheritdoc IOffers
    function getOfferSignatureStatus(bytes memory signature) external view returns (bool) {
        return _cancelledOrFinalized[signature];
    }

    /// @inheritdoc IOffers
    function withdrawOfferSignature(Offer memory offer, bytes memory signature)
        external
        whenNotPaused
    {
        requireAvailableSignature(signature);
        requireSignature65(signature);

        address signer = getOfferSigner(offer, signature);

        _requireSigner(signer, msg.sender);
        _requireOfferCreator(offer.creator, msg.sender);

        _markSignatureUsed(offer, signature);
    }

    /// @inheritdoc IOffers
    function getOffer(
        bytes32 offerHash
    ) public view returns (Offer memory) {
        return _nftOfferBooks[offerHash];
    }

    /// @inheritdoc IOffers
    function getFloorOfferCount(bytes32 offerHash) public view returns (uint64 count) {
        return _floorOfferCounters[offerHash];
    }

    /// @inheritdoc IOffers
    function getSigFloorOfferCount(bytes memory signature) public view returns (uint64 count) {
        return _sigFloorOfferCounters[signature];
    }

    /// @inheritdoc IOffers
    function incrementFloorOfferCount(bytes32 offerHash) public {
        _requireExpectedContract();
        _floorOfferCounters[offerHash] += 1;
    }

    /// @inheritdoc IOffers
    function incrementSigFloorOfferCount(bytes memory signature) public {
        _requireSigLendingContract();
        _sigFloorOfferCounters[signature] += 1;
    }

    /// @inheritdoc IOffers
    function createOffer(Offer memory offer) external whenNotPaused returns (bytes32 offerHash) {
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);

        _requireOfferNotExpired(offer);
        requireMinimumDuration(offer);
        _requireOfferCreator(offer.creator, msg.sender);

        if (offer.lenderOffer) {
            uint256 offerTokens = ILiquidity(liquidityContractAddress).assetAmountToCAssetAmount(
                offer.asset,
                offer.amount
            );
            if (offer.nftContractAddress.supportsInterface(type(IERC1155Upgradeable).interfaceId)) {
                _requireNonFungibleToken(
                    offer.nftContractAddress,
                    offer.nftId
                );
            }
            _requireCAssetBalance(msg.sender, cAsset, offerTokens);
        } else {
            _requireNftOwner(msg.sender, offer.nftContractAddress, offer.nftId);
            requireNoFloorTerms(offer);
        }

        offerHash = getOfferHash(offer);

        _requireOfferDoesntExist(_nftOfferBooks[offerHash].creator);

        _nftOfferBooks[offerHash] = offer;

        emit NewOffer(offer.creator, offer.nftContractAddress, offer.nftId, offer, offerHash);
    }

    /// @inheritdoc IOffers
    function removeOffer(bytes32 offerHash) external whenNotPaused {
        Offer storage offer = _nftOfferBooks[offerHash];

        _requireOfferCreatorOrExpectedContract(offer.creator, msg.sender);

        emit OfferRemoved(offer.creator, offer.nftContractAddress, offer.nftId, offer, offerHash);

        delete _nftOfferBooks[offerHash];
    }

    /// @inheritdoc IOffers
    function markSignatureUsed(Offer memory offer, bytes memory signature) external {
        require(msg.sender == sigLendingContractAddress, "00031");
        _markSignatureUsed(offer, signature);
    }

    function _markSignatureUsed(Offer memory offer, bytes memory signature) internal {
        _cancelledOrFinalized[signature] = true;

        emit OfferSignatureUsed(offer.nftContractAddress, offer.nftId, offer, signature);
    }

    /// @inheritdoc IOffers
    function requireAvailableSignature(bytes memory signature) public view {
        require(!_cancelledOrFinalized[signature], "00032");
    }

    /// @inheritdoc IOffers
    function requireSignature65(bytes memory signature) public pure {
        require(signature.length == 65, "00003");
    }

    /// @inheritdoc IOffers
    function requireMinimumDuration(Offer memory offer) public pure {
        require(offer.duration >= 1 days, "00011");
    }

    /// @inheritdoc IOffers
    function requireNoFloorTerms(Offer memory offer) public pure {
        require(!offer.floorTerm, "00014");
    }

    function _requireOfferNotExpired(Offer memory offer) internal view {
        require(offer.expiration > SafeCastUpgradeable.toUint32(block.timestamp), "00010");
    }

    function _requireNftOwner(
        address owner,
        address nftContractAddress,
        uint256 nftId
    ) internal view {
        if (nftContractAddress.supportsInterface(type(IERC1155Upgradeable).interfaceId)) {
            _requireNonFungibleToken(
                nftContractAddress,
                nftId
            );
            _require1155NftOwner(
                owner,
                nftContractAddress,
                nftId
            );
        } else {
            _require721Owner(
                nftContractAddress,
                nftId,
                owner
            );
        }
    }

    function _require721Owner(
        address nftContractAddress,
        uint256 nftId,
        address owner
    ) internal view {
        require(IERC721Upgradeable(nftContractAddress).ownerOf(nftId) == owner, "00021");
    }

    function _require1155NftOwner(
        address owner,
        address nftContractAddress,
        uint256 nftId
    ) internal view {
        require(IERC1155SupplyUpgradeable(nftContractAddress).balanceOf(owner, nftId) == 1, "00021");
    }

    function _requireNonFungibleToken(
        address nftContractAddress,
        uint256 nftId
    ) internal view {
        require(IERC1155SupplyUpgradeable(nftContractAddress).totalSupply(nftId) == 1, "00070");
    }

    function _requireSigner(address signer, address expected) internal pure {
        require(signer == expected, "00033");
    }

    function _requireOfferCreator(address signer, address expected) internal pure {
        require(signer == expected, "00024");
    }

    function _requireOfferCreatorOrExpectedContract(address signer, address expected)
        internal
        view
    {
        require(
            signer == expected ||
            msg.sender == lendingContractAddress ||
            msg.sender == flashPurchaseContractAddress ||
            msg.sender == refinanceContractAddress,
            "00024"
        );
    }

    function _requireExpectedContract() internal view {
        require(msg.sender == lendingContractAddress || msg.sender == flashPurchaseContractAddress || msg.sender == refinanceContractAddress, "00024");
    }

    function _requireSigLendingContract() internal view {
        require(msg.sender == sigLendingContractAddress, "00024");
    }

    function _requireOfferDoesntExist(address offerCreator) internal pure {
        require(offerCreator == address(0), "00046");
    }

    function _requireCAssetBalance(
        address account,
        address cAsset,
        uint256 amount
    ) internal view {
        require(
            ILiquidity(liquidityContractAddress).getCAssetBalance(account, cAsset) >= amount,
            "00034"
        );
    }

    function renounceOwnership() public override onlyOwner {}
}
