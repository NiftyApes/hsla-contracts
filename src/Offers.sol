//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "./interfaces/niftyapes/offers/IOffers.sol";
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./lib/ECDSABridge.sol";

/// @title Implemention of the IOffers interface
contract NiftyApesOffers is OwnableUpgradeable, PausableUpgradeable, EIP712Upgradeable, IOffers {
    using AddressUpgradeable for address payable;

    /// @dev A mapping for a NFT to an Offer
    ///      The mapping has to be broken into three parts since an NFT is denomiated by its address (first part)
    ///      and its nftId (second part), offers are reffered to by their hash (see #getEIP712EncodedOffer for details) (third part).
    mapping(address => mapping(uint256 => mapping(bytes32 => Offer))) private _nftOfferBooks;

    /// @dev A mapping for a NFT to a floor offer
    ///      Floor offers are different from offers on a specific NFT since they are valid on any NFT fro the same address.
    ///      Thus this mapping skips the nftId, see _nftOfferBooks above.
    mapping(address => mapping(bytes32 => Offer)) private _floorOfferBooks;

    /// @dev A mapping to mark a signature as used.
    ///      The mapping allows users to withdraw offers that they made by signature.
    mapping(bytes => bool) private _cancelledOrFinalized;

    /// @inheritdoc IOffers
    address public lendingContractAddress;

    /// @inheritdoc IOffers
    address public liquidityContractAddress;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the NiftyApes protocol.
    ///         NiftyApes is intended to be deployed behind a proxy and thus needs to initialize
    ///         its state outside of a constructor.
    function initialize() public initializer {
        EIP712Upgradeable.__EIP712_init("NiftyApes_Offers", "0.0.1");

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
    }

    /// @inheritdoc IOffersAdmin
    function updateLendingContractAddress(address newLendingContractAddress) external onlyOwner {
        emit OffersXLendingContractAddressUpdated(
            lendingContractAddress,
            newLendingContractAddress
        );
        lendingContractAddress = newLendingContractAddress;
    }

    /// @inheritdoc IOffersAdmin
    function updateLiquidityContractAddress(address newLiquidityContractAddress)
        external
        onlyOwner
    {
        emit OffersXLiquidityContractAddressUpdated(
            liquidityContractAddress,
            newLiquidityContractAddress
        );
        liquidityContractAddress = newLiquidityContractAddress;
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
                        keccak256(
                            "Offer(address creator,uint32 duration,uint32 expiration,bool fixedTerms,bool floorTerm,bool lenderOffer,address nftContractAddress,uint256 nftId,address asset,uint128 amount,uint96 interestRatePerSecond)"
                        ),
                        keccak256(
                            abi.encode(
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
                                offer.interestRatePerSecond
                            )
                        )
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
        _requireAvailableSignature(signature);
        _requireSignature65(signature);

        address signer = getOfferSigner(offer, signature);

        _requireSigner(signer, msg.sender);
        _requireOfferCreator(offer.creator, msg.sender);

        _markSignatureUsed(offer, signature);
    }

    function _getOfferBook(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm
    ) internal view returns (mapping(bytes32 => Offer) storage) {
        return
            floorTerm
                ? _floorOfferBooks[nftContractAddress]
                : _nftOfferBooks[nftContractAddress][nftId];
    }

    /// @inheritdoc IOffers
    function getOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) public view returns (Offer memory) {
        return _getOfferInternal(nftContractAddress, nftId, offerHash, floorTerm);
    }

    function _getOfferInternal(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) internal view returns (Offer storage) {
        return _getOfferBook(nftContractAddress, nftId, floorTerm)[offerHash];
    }

    /// @inheritdoc IOffers
    function createOffer(Offer memory offer) external whenNotPaused returns (bytes32 offerHash) {
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);

        _requireOfferCreator(offer.creator, msg.sender);

        if (offer.lenderOffer) {
            uint256 offerTokens = ILiquidity(liquidityContractAddress).assetAmountToCAssetAmount(
                offer.asset,
                offer.amount
            );
            _requireCAssetBalance(msg.sender, cAsset, offerTokens);
        } else {
            _requireNftOwner(offer.nftContractAddress, offer.nftId, msg.sender);
            _requireNoFloorTerms(offer);
        }

        mapping(bytes32 => Offer) storage offerBook = _getOfferBook(
            offer.nftContractAddress,
            offer.nftId,
            offer.floorTerm
        );

        offerHash = getOfferHash(offer);

        offerBook[offerHash] = offer;

        emit NewOffer(
            offer.creator,
            offer.asset,
            offer.nftContractAddress,
            offer.nftId,
            offer,
            offerHash
        );
    }

    /// @inheritdoc IOffers
    function removeOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external whenNotPaused {
        Offer memory offer = getOffer(nftContractAddress, nftId, offerHash, floorTerm);

        _requireOfferCreator(offer.creator, msg.sender);

        _doRemoveOffer(nftContractAddress, nftId, offerHash, floorTerm);
    }

    function _doRemoveOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) internal {
        mapping(bytes32 => Offer) storage offerBook = _getOfferBook(
            nftContractAddress,
            nftId,
            floorTerm
        );

        Offer storage offer = offerBook[offerHash];

        emit OfferRemoved(
            offer.creator,
            offer.asset,
            offer.nftContractAddress,
            nftId,
            offer,
            offerHash
        );

        delete offerBook[offerHash];
    }

    /// @inheritdoc IOffers
    function markSignatureUsed(Offer memory offer, bytes memory signature) external {
        require(msg.sender == lendingContractAddress, "not authorized");
        _markSignatureUsed(offer, signature);
    }

    function _markSignatureUsed(Offer memory offer, bytes memory signature) internal {
        _cancelledOrFinalized[signature] = true;

        emit OfferSignatureUsed(offer.nftContractAddress, offer.nftId, offer, signature);
    }

    /// @inheritdoc IOffers
    function requireAvailableSignature(bytes memory signature) public view {
        require(!_cancelledOrFinalized[signature], "signature not available");
    }

    /// @inheritdoc IOffers
    function requireSignature65(bytes memory signature) public pure {
        require(signature.length == 65, "signature unsupported");
    }

    function _requireNoFloorTerms(Offer memory offer) internal pure {
        require(!offer.floorTerm, "floor term");
    }

    function _requireNftOwner(
        address nftContractAddress,
        uint256 nftId,
        address owner
    ) internal view {
        require(IERC721Upgradeable(nftContractAddress).ownerOf(nftId) == owner, "nft owner");
    }

    function _requireSigner(address signer, address expected) internal pure {
        require(signer == expected, "signer");
    }

    function _requireOfferCreator(address signer, address expected) internal view {
        if (msg.sender != lendingContractAddress) {
            require(signer == expected, "offer creator");
        }
    }

    function _requireCAssetBalance(
        address account,
        address cAsset,
        uint256 amount
    ) internal view {
        require(
            ILiquidity(liquidityContractAddress).getCAssetBalance(account, cAsset) >= amount,
            "Insufficient cToken balance"
        );
    }

    function renounceOwnership() public override onlyOwner {}
}
