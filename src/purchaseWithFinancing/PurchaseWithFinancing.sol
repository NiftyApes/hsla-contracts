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
import "../interfaces/niftyapes/purchaseWithFinancing/IPurchaseWithFinancing.sol";
import "../interfaces/niftyapes/lending/ILending.sol";
import "../interfaces/niftyapes/sigLending/ISigLending.sol";
import "./integrations/IFinanceReceiver.sol";
import "../interfaces/niftyapes/liquidity/ILiquidity.sol";
import "../interfaces/niftyapes/offers/IOffers.sol";
import "../interfaces/sanctions/SanctionsList.sol";

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
    function initialize() public initializer {
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
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
    function borrow(
        bytes32 offerHash,
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm,
        address receiver,
        address borrower,
        bytes calldata data
    ) external payable whenNotPaused nonReentrant {
        Offer memory offer = _fetchAndRemoveNonFloorOffer(
            nftContractAddress,
            offerHash,
            floorTerm,
            nftId
        );
        if (!floorTerm) {
            _requireMatchingNftId(offer, nftId);
        }
        _doBorrow(offer, nftId, receiver, borrower, data);
    }

    /// @inheritdoc IPurchaseWithFinancing
    function borrowSignature(
        Offer memory offer,
        bytes memory signature,
        uint256 nftId,
        address receiver,
        address borrower,
        bytes calldata data
    ) external payable whenNotPaused nonReentrant {
        ISigLending(sigLendingContractAddress).validateAndUseOfferSignature(offer, signature, nftId);
        _doBorrow(offer, nftId, receiver, borrower, data);
    }

    function _doBorrow(
        Offer memory offer,
        uint256 nftId,
        address receiver,
        address borrower,
        bytes calldata data
    ) internal {
        _requireIsNotSanctioned(offer.creator);
        _requireIsNotSanctioned(borrower);
        _requireIsNotSanctioned(receiver);
        // requireOfferisValid
        require(offer.asset != address(0), "00004");
        _requireLenderOffer(offer);
        _requireOfferNotExpired(offer);
        _requireMinDurationForOffer(offer);
        
        LoanAuction memory loanAuction = ILending(lendingContractAddress).getLoanAuction(
            offer.nftContractAddress,
            nftId
        );
        // requireNoOpenLoan
        require(loanAuction.lastUpdatedTimestamp == 0, "00006");

        // redeem required underlying asset from Compound
        uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
            offer.asset,
            offer.amount
        );
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(offer.asset);
        // subtract loaned amount from lender's balance
        ILiquidity(liquidityContractAddress).withdrawCBalance(offer.creator, cAsset, cTokensBurned);

        // initiate a loan between lender and borrower
        ILending(lendingContractAddress).createLoan(
            offer,
            nftId,
            offer.creator,
            borrower
        );

        // send funds to reciever
        ILiquidity(liquidityContractAddress).sendValue(offer.asset, offer.amount, receiver);

        // execute opreation on receiver contract
        require(IFinanceReceiver(receiver).executeOperation(
            offer.nftContractAddress,
            nftId,
            msg.sender,
            data
        ), "00052");
        
        // Transfer nft from receiver contract to lending contract as collateral, revert on failure
        _transferNft(
            offer.nftContractAddress,
            nftId,
            address(this),
            lendingContractAddress
        );

        emit LoanExecutedForPurchase(
            offer.nftContractAddress,
            nftId,
            receiver,
            loanAuction
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

    function _fetchAndRemoveNonFloorOffer(
        address nftContractAddress,
        bytes32 offerHash,
        bool floorTerm,
        uint256 nftId
    ) internal returns(Offer memory offer) {
        // fetch offer
        offer = IOffers(offersContractAddress).getOffer(
            nftContractAddress,
            nftId,
            offerHash,
            floorTerm
        );

        // remove non-floor offer
        if (!offer.floorTerm) {
            _requireMatchingNftId(offer, nftId);
            IOffers(offersContractAddress).removeOffer(
                offer.nftContractAddress,
                nftId,
                offerHash,
                floorTerm
            );
        }
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

    function _requireIsNotSanctioned(address addressToCheck) internal view {
        if (!_sanctionsPause) {
            SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
            bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
            require(!isToSanctioned, "00017");
        }
    }

    /// @notice This contract needs to accept ETH to acquire enough funds to purchase NFTs
    receive() external payable {
        _requireEthTransferable();
    }
}
