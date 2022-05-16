//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "./interfaces/compound/ICEther.sol";
import "./interfaces/compound/ICERC20.sol";
import "./interfaces/niftyapes/offers/IOffers.sol";
import "./interfaces/niftyapes/INiftyApes.sol";
import "./interfaces/sanctions/SanctionsList.sol";
import "./lib/ECDSABridge.sol";
import "./lib/Math.sol";
// import "./test/Console.sol";

/// @title Implemention of the IOffers interface
contract NiftyApesOffers is
    OwnableUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable,
    IOffers,
    INiftyApes
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    //TODO: (Captnseagraves) do we need to impose sanctions on offers? 
    /// @dev Internal constant address for the Chinalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

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

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the NiftyApes protocol.
    ///         Nifty Apes is intended to be deployed behind a proxy amd thus needs to initialize
    ///         its state outsize of a constructor.
    function initialize() public initializer {
        EIP712Upgradeable.__EIP712_init("NiftyApes_Offers", "0.0.1");

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
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
    function getOfferSignatureStatus(bytes memory signature) external view returns (bool) {
        return _cancelledOrFinalized[signature];
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
    function withdrawOfferSignature(Offer memory offer, bytes memory signature)
        external
        whenNotPaused
    {
        requireAvailableSignature(signature);
        requireSignature65(signature);

        address signer = getOfferSigner(offer, signature);

        requireSigner(signer, msg.sender);
        requireOfferCreator(offer, msg.sender);

        markSignatureUsed(offer, signature);
    }

    function getOfferBook(
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
        return getOfferInternal(nftContractAddress, nftId, offerHash, floorTerm);
    }

    function getOfferInternal(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) internal view returns (Offer storage) {
        return getOfferBook(nftContractAddress, nftId, floorTerm)[offerHash];
    }

    /// @inheritdoc IOffers
    function createOffer(Offer memory offer) external whenNotPaused returns (bytes32 offerHash) {
        address cAsset = INiftyApes.getCAsset(offer.asset);

        requireOfferCreator(offer.creator, msg.sender);

        if (offer.lenderOffer) {
            uint256 offerTokens = assetAmountToCAssetAmount(offer.asset, offer.amount);
            requireCAssetBalance(msg.sender, cAsset, offerTokens);
        } else {
            requireNftOwner(offer.nftContractAddress, offer.nftId, msg.sender);
            requireNoFloorTerms(offer);
        }

        mapping(bytes32 => Offer) storage offerBook = getOfferBook(
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

        requireOfferCreator(offer.creator, msg.sender);

        doRemoveOffer(nftContractAddress, nftId, offerHash, floorTerm);
    }

    function doRemoveOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) internal whenNotPaused {
        mapping(bytes32 => Offer) storage offerBook = getOfferBook(
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

   
    function markSignatureUsed(Offer memory offer, bytes memory signature) internal {
        _cancelledOrFinalized[signature] = true;

        emit OfferSignatureUsed(offer.nftContractAddress, offer.nftId, offer, signature);
    }

    

    function requireSignature65(bytes memory signature) internal pure {
        require(signature.length == 65, "signature unsupported");
    }

    function requireNoFloorTerms(Offer memory offer) internal pure {
        require(!offer.floorTerm, "floor term");
    }

    function requireIsNotSanctioned(
        address addressToCheck
    ) internal view {
        SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
        bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
        require(!isToSanctioned, "sanctioned address");
    }

    function requireNftOwner(
        address nftContractAddress,
        uint256 nftId,
        address owner
    ) internal view {
        require(IERC721Upgradeable(nftContractAddress).ownerOf(nftId) == owner, "nft owner");
    }

    function requireAvailableSignature(bytes memory signature) internal view {
        require(!_cancelledOrFinalized[signature], "signature not available");
    }

    function requireOfferCreator(Offer memory offer, address creator) internal pure {
        require(creator == offer.creator, "offer creator mismatch");
    }

    function requireSigner(address signer, address expected) internal pure {
        require(signer == expected, "signer");
    }

    function requireOfferCreator(address signer, address expected) internal pure {
        require(signer == expected, "offer creator");
    }

    function requireCAssetBalance(
        address account,
        address cAsset,
        uint256 amount
    ) internal view {
        require(getCAssetBalance(account, cAsset) >= amount, "Insufficient cToken balance");
    }

    function currentTimestamp() internal view returns (uint32) {
        return SafeCastUpgradeable.toUint32(block.timestamp);
    }

    // This is needed to receive ETH when calling withdrawing ETH from compund
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {
        require(_ethTransferable, "eth not transferable");
    }

    function renounceOwnership() public override onlyOwner {}
}
