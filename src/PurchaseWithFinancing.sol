//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "./Lending.sol";
import "./interfaces/niftyapes/purchaseWithFinancing/IPurchaseWithFinacing.sol";
import "./interfaces/niftyapes/purchaseWithFinancing/ISeaport.sol";
import "forge-std/Test.sol";

/// @notice Extension of NiftApes lending contract to allow for OpenSea purchases
contract PurchaseWithFinancing is NiftyApesLending, IPurchaseWithFinancing {
    ISeaport public seaport;

    /// @dev this should be taken from `Lending.sol` but it's marked private and not internal.
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @notice Mutex to selectively enable ETH transfers
    /// @dev    Follows a similar pattern to `Liquidiy.sol`
    bool internal _ethTransferable = false;

    /// @notice Constructor to take set the OpenSea Seaport address
    constructor(address _seaportAddress) {
        seaport = ISeaport(_seaportAddress);
    }

    /// @notice This contract needs to accept ETH to acquire enough funds to purchase NFTs
    receive() external payable {
        _requireEthTransferable();
    }

    /// @notice Allows a user to borrow ETH to purchase NFTs.
    ///         borrower = msg.sender, lender = offer.creator
    /// @param nftId Id of NFT contract borrower would like to purchase
    /// @param offerHash Hash of the existing offer in Nifty
    /// @param floorTerm Determines if this is a floor offer or not.
    /// @param order Seaport parameters the caller is expected to fill out.
    /// @dev The OrderParametrs are EIP712 compliant with a signature field in the struct.
    ///      This will be enforced and verified by OpenSea, not this function.
    function purchaseWithFinancingOpenSea(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm,
        ISeaport.BasicOrderParameters calldata order
    ) external payable whenNotPaused nonReentrant {
        Offer memory offer = IOffers(offersContractAddress).getOffer(
            nftContractAddress,
            nftId,
            offerHash,
            floorTerm
        );

        _requireLenderOffer(offer);
        _requireOfferNotExpired(offer);
        _requireMinDurationForOffer(offer);

        _requireMatchingNFTContract(offer.nftContractAddress, order.offerToken);
        if (!offer.floorTerm) {
            _requireMatchingNftId(offer, order.offerIdentifier);
            IOffers(offersContractAddress).removeOffer(
                offer.nftContractAddress,
                offer.nftId,
                offerHash,
                floorTerm
            );
        }

        // Ensure both assets are native ETH
        _requireMatchingAsset(offer.asset, ETH_ADDRESS);
        _requireSeaportNativeETH(order);

        // _requireIsNotSanctioned(offer.creator);
        // _requireIsNotSanctioned(msg.sender);

        // Ensure enough ETH has been sent in to purchase with NFT (with the help of lender)
        uint256 purchaseAmount = msg.value + offer.amount;
        require(purchaseAmount == order.considerationAmount, "00103"); // "Not enough ETH to purchase NFT"

        // Lender liquidates the borrowed amount to the Liquidity contract
        uint256 cTokensBurned = ILiquidity(liquidityContractAddress).burnCErc20(
            offer.asset,
            offer.amount
        );

        // Do some internal accounting so that Liquidity contract knows lender has less balance
        address cAsset = ILiquidity(liquidityContractAddress).getCAsset(ETH_ADDRESS);
        ILiquidity(liquidityContractAddress).withdrawCBalance(offer.creator, cAsset, cTokensBurned);

        // Transfer liquidated funds from Liquidity contract to this contract
        _ethTransferable = true;
        ILiquidity(liquidityContractAddress).sendValue(offer.asset, offer.amount, address(this));
        _ethTransferable = false;

        // Purchase NFT
        bool success = seaport.fulfillBasicOrder{ value: purchaseAmount }(order);
        require(success, "00101");
        require(
            IERC721Upgradeable(offer.nftContractAddress).ownerOf(nftId) == address(this),
            "00018"
        );

        // Transfer purchased NFT to borrower
        _transferNft(offer.nftContractAddress, nftId, address(this), msg.sender);

        // Update loanAuction struct (this should be similar functionality to `_createLoan()`);
        LoanAuction storage loanAuction = _getLoanAuctionInternal(
            offer.nftContractAddress,
            offer.nftId
        );
        _createSeaportLoan(loanAuction, offer);

        emit LoanExecutedForOpenSea(offer.nftContractAddress, offer.nftId, offer);
    }

    /// @dev based off of _createLoan() in Lender.sol
    function _createSeaportLoan(LoanAuction storage loanAuction, Offer memory offer) internal {
        loanAuction.nftOwner = msg.sender;
        loanAuction.lender = offer.creator;
        loanAuction.asset = offer.asset;
        loanAuction.amount = offer.amount;
        loanAuction.loanEndTimestamp = _currentTimestamp32() + offer.duration;
        loanAuction.loanBeginTimestamp = _currentTimestamp32();
        loanAuction.lastUpdatedTimestamp = _currentTimestamp32();
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;
        loanAuction.lenderRefi = false;
        loanAuction.accumulatedLenderInterest = 0;
        loanAuction.accumulatedProtocolInterest = 0;
        loanAuction.interestRatePerSecond = offer.interestRatePerSecond;
        loanAuction.protocolInterestRatePerSecond = calculateInterestPerSecond(
            offer.amount,
            protocolInterestBps,
            offer.duration
        );
        console.log(
            "createSeaportLoan loanAuction.protocolInterestRatePerSecond",
            loanAuction.protocolInterestRatePerSecond
        );
        loanAuction.slashableLenderInterest = 0;
    }

    /// @notice Allow for contract to receive safe ERC721 transfers
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _requireMatchingNFTContract(address nftAddress1, address nftAddress2) internal pure {
        require(nftAddress1 == nftAddress2, "00102");
    }

    function _requireSeaportNativeETH(ISeaport.BasicOrderParameters calldata order) internal pure {
        require(order.considerationToken == address(0), "00102");
    }

    function _requireEthTransferable() internal view {
        require(_ethTransferable, "00043");
    }
}
