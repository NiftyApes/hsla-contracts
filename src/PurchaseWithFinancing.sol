//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "./interfaces/niftyapes/purchaseWithFinancing/IPurchaseWithFinancing.sol";
import "./interfaces/niftyapes/lending/ILending.sol";
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./interfaces/niftyapes/offers/IOffers.sol";
import "./interfaces/sanctions/SanctionsList.sol";
import "./interfaces/seaport/ISeaport.sol";
import "forge-std/Test.sol";

/// @notice Extension of NiftApes lending contract to allow for Seaport purchases
contract NiftyApesPurchaseWithFinancing is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    IPurchaseWithFinancing
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    /// @dev Internal address used for for ETH
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Internal constant address for the Chainalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    /// @inheritdoc IPurchaseWithFinancing
    address public offersContractAddress;

    /// @inheritdoc IPurchaseWithFinancing
    address public liquidityContractAddress;

    /// @inheritdoc IPurchaseWithFinancing
    address public lendingContractAddress;

    /// @inheritdoc IPurchaseWithFinancing
    address public sigLendingContractAddress;

    /// @inheritdoc IPurchaseWithFinancing
    address public seaportContractAddress;

    /// @notice Mutex to selectively enable ETH transfers
    /// @dev    Follows a similar pattern to `Liquidiy.sol`
    bool internal _ethTransferable = false;

    /// @dev The status of sanctions checks. Can be set to false if oracle becomes malicious.
    bool internal _sanctionsPause;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the NiftyApes protocol.
    ///         Nifty Apes is intended to be deployed behind a proxy amd thus needs to initialize
    ///         its state outsize of a constructor.
    function initialize(address newSeaportContractAddress) public initializer {
        seaportContractAddress = newSeaportContractAddress;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function updateLiquidityContractAddress(address newLiquidityContractAddress)
        external
        onlyOwner
    {
        require(address(newLiquidityContractAddress) != address(0), "00035");
        emit PurchaseWithFinancingXLiquidityContractAddressUpdated(
            liquidityContractAddress,
            newLiquidityContractAddress
        );
        liquidityContractAddress = newLiquidityContractAddress;
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function updateOffersContractAddress(address newOffersContractAddress) external onlyOwner {
        require(address(newOffersContractAddress) != address(0), "00035");
        emit PurchaseWithFinancingXOffersContractAddressUpdated(
            offersContractAddress,
            newOffersContractAddress
        );
        offersContractAddress = newOffersContractAddress;
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function updateLendingContractAddress(address newLendingContractAddress) external onlyOwner {
        require(address(newLendingContractAddress) != address(0), "00035");
        emit PurchaseWithFinancingXLendingContractAddressUpdated(
            lendingContractAddress,
            newLendingContractAddress
        );
        lendingContractAddress = newLendingContractAddress;
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function updateSigLendingContractAddress(address newSigLendingContractAddress)
        external
        onlyOwner
    {
        require(address(newSigLendingContractAddress) != address(0), "00035");
        emit PurchaseWithFinancingXSigLendingContractAddressUpdated(
            sigLendingContractAddress,
            newSigLendingContractAddress
        );
        sigLendingContractAddress = newSigLendingContractAddress;
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function updateSeaportContractAddress(address newSeaportContractAddress) external onlyOwner {
        emit SeaportContractAddressUpdated(newSeaportContractAddress);
        seaportContractAddress = newSeaportContractAddress;
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function pauseSanctions() external onlyOwner {
        _sanctionsPause = true;
        emit PurchaseWithFinancingSanctionsPaused();
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function unpauseSanctions() external onlyOwner {
        _sanctionsPause = false;
        emit PurchaseWithFinancingSanctionsUnpaused();
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IPurchaseWithFinancingAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IPurchaseWithFinancing
    function purchaseWithFinancingSeaport(
        address nftContractAddress,
        bytes32 offerHash,
        bool floorTerm,
        ISeaport.Order calldata order,
        bytes32 fulfillerConduitKey
    ) external payable whenNotPaused nonReentrant {
        Offer memory offer = IOffers(offersContractAddress).getOffer(
            nftContractAddress,
            order.parameters.offer[0].identifierOrCriteria,
            offerHash,
            floorTerm
        );

        if (!offer.floorTerm) {
            _requireMatchingNftId(offer, order.parameters.offer[0].identifierOrCriteria);
            IOffers(offersContractAddress).removeOffer(
                offer.nftContractAddress,
                order.parameters.offer[0].identifierOrCriteria,
                offerHash,
                floorTerm
            );
        }
        _doPurchaseWithFinancingSeaport(
            offer,
            offer.creator,
            msg.sender,
            order,
            msg.value,
            fulfillerConduitKey
        );
    }

    /// @inheritdoc IPurchaseWithFinancing
    function doPurchaseWithFinancingSeaport(
        Offer memory offer,
        address lender,
        address borrower,
        ISeaport.Order calldata order,
        uint256 msgValue,
        bytes32 fulfillerConduitKey
    ) external payable whenNotPaused nonReentrant {
        _requireSigLendingContract();
        _doPurchaseWithFinancingSeaport(
            offer,
            lender,
            borrower,
            order,
            msgValue,
            fulfillerConduitKey
        );
    }

    function _doPurchaseWithFinancingSeaport(
        Offer memory offer,
        address lender,
        address borrower,
        ISeaport.Order calldata order,
        uint256 msgValue,
        bytes32 fulfillerConduitKey
    ) internal {
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);

        LoanAuction memory loanAuction = ILending(lendingContractAddress).getLoanAuction(
            offer.nftContractAddress,
            offer.nftId
        );

        _requireIsNotSanctioned(lender);
        _requireIsNotSanctioned(borrower);
        // requireOfferPresent
        require(offer.asset != address(0), "00004");
        _requireLenderOffer(offer);
        _requireOfferNotExpired(offer);
        _requireMinDurationForOffer(offer);
        // requireNoOpenLoan
        require(loanAuction.lastUpdatedTimestamp == 0, "00006");
        _requireMatchingAsset(offer.asset, order.parameters.consideration[0].token);
        _requireMatchingNFTContract(offer.nftContractAddress, order.parameters.offer[0].token);
        // requireOrderTokenERC721
        require(order.parameters.offer[0].itemType == ISeaport.ItemType.ERC721, "00049");
        // requireOrderTokenAmount
        require(order.parameters.offer[0].startAmount == 1, "00049");
        // requireOrderNotAuction
        require(
            order.parameters.consideration[0].startAmount ==
                order.parameters.consideration[0].endAmount,
            "00049"
        );

        uint256 considerationAmount;

        for (uint256 i = 0; i < order.parameters.totalOriginalConsiderationItems - 1; i++) {
            considerationAmount += order.parameters.consideration[i].endAmount;
        }

        uint256 considerationDelta = considerationAmount - offer.amount;

        if (offer.asset == ETH_ADDRESS) {
            require(msgValue >= considerationDelta, "00047");
            if (msgValue > considerationDelta) {
                payable(borrower).sendValue(msgValue - considerationDelta);
            }
        } else {
            IERC20Upgradeable asset = IERC20Upgradeable(offer.asset);
            asset.safeTransferFrom(borrower, address(this), considerationDelta);

            uint256 allowance = asset.allowance(address(this), address(cAsset));
            if (allowance > 0) {
                asset.safeDecreaseAllowance(cAsset, allowance);
            }
            asset.safeIncreaseAllowance(cAsset, considerationDelta);
        }

        uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
            offer.asset,
            offer.amount
        );

        ILiquidity(liquidityContractAddress).withdrawCBalance(offer.creator, cAsset, cTokensBurned);

        _ethTransferable = true;
        ILiquidity(liquidityContractAddress).sendValue(offer.asset, offer.amount, address(this));
        _ethTransferable = false;

        // Purchase NFT
        require(
            ISeaport(seaportContractAddress).fulfillOrder{ value: considerationAmount }(
                order,
                bytes32(0)
            ),
            "00048"
        );

        // Transfer purchased NFT to Lending.sol
        _transferNft(
            offer.nftContractAddress,
            order.parameters.offer[0].identifierOrCriteria,
            address(this),
            lendingContractAddress
        );

        ILending(lendingContractAddress).createLoan(
            offer,
            order.parameters.offer[0].identifierOrCriteria,
            offer.creator,
            msg.sender
        );

        emit LoanExecutedSeaport(
            offer.nftContractAddress,
            order.parameters.offer[0].identifierOrCriteria,
            offer
        );
    }

    function _transferNft(
        address nftContractAddress,
        uint256 nftId,
        address from,
        address to
    ) internal {
        IERC721Upgradeable(nftContractAddress).safeTransferFrom(from, to, nftId);
    }

    function _requireMatchingNFTContract(address nftAddress1, address nftAddress2) internal pure {
        require(nftAddress1 == nftAddress2, "00102");
    }

    // redundant function to other contracts

    function _requireEthTransferable() internal view {
        require(_ethTransferable, "00043");
    }

    function _requireMatchingNftId(Offer memory offer, uint256 nftId) internal pure {
        require(nftId == offer.nftId, "00022");
    }

    function _requireLenderOffer(Offer memory offer) internal pure {
        require(offer.lenderOffer, "00012");
    }

    function _requireOfferNotExpired(Offer memory offer) internal view {
        require(offer.expiration > SafeCastUpgradeable.toUint32(block.timestamp), "00010");
    }

    function _requireMinDurationForOffer(Offer memory offer) internal pure {
        require(offer.duration >= 1 days, "00011");
    }

    function _requireMatchingAsset(address asset1, address asset2) internal pure {
        if (asset2 == address(0)) {
            require(asset1 == ETH_ADDRESS, "00019");
        } else {
            require(asset1 == asset2, "00019");
        }
    }

    function _requireIsNotSanctioned(address addressToCheck) internal view {
        if (!_sanctionsPause) {
            SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
            bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
            require(!isToSanctioned, "00017");
        }
    }

    function _requireSigLendingContract() internal view {
        require(msg.sender == sigLendingContractAddress, "00031");
    }

    /// @notice This contract needs to accept ETH to acquire enough funds to purchase NFTs
    receive() external payable {
        _requireEthTransferable();
    }
}
