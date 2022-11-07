//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "./interfaces/niftyapes/sellOnSeaport/ISellOnSeaport.sol";
import "./interfaces/niftyapes/lending/ILending.sol";
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./interfaces/sanctions/SanctionsList.sol";
import "./flashSell/interfaces/IFlashSellReceiver.sol";

import "forge-std/Test.sol";

/// @notice Extension of NiftApes lending contract to allow sale of NFTs on Seaport for closure of loans
/// @title SellOnSeaport
/// @custom:version 1.0
/// @author zishansami102 (zishansami.eth)
contract NiftyApesSellOnSeaport is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    ISellOnSeaport,
    IFlashSellReceiver
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    /// @dev Internal address used for for ETH
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Internal constant address for the Chainalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    /// @notice The base value for fees in the protocol.
    uint256 private constant MAX_BPS = 10_000;

    /// @dev A mapping for storing the seaport listing with its hash as the key
    mapping(bytes32 => SeaportListing) private _orderHashToListing;

    /// @inheritdoc ISellOnSeaport
    address public liquidityContractAddress;

    /// @inheritdoc ISellOnSeaport
    address public lendingContractAddress;

    /// @inheritdoc ISellOnSeaport
    address public seaportContractAddress;

    /// @inheritdoc ISellOnSeaport
    address public flashSellContractAddress;

    /// @inheritdoc ISellOnSeaport
    address public wethContractAddress;

    /// @inheritdoc ISellOnSeaport
    address public openseaZone;

    /// @inheritdoc ISellOnSeaport
    address public openseaFeeRecepient;

    /// @inheritdoc ISellOnSeaport
    bytes32 public openseaZoneHash;

    /// @inheritdoc ISellOnSeaport
    bytes32 public openseaConduitKey;

    /// @inheritdoc ISellOnSeaport
    address public openseaConduit;

    /// @dev The status of sanctions checks. Can be set to false if oracle becomes malicious.
    bool internal _sanctionsPause;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the SellOnSeaport Contract.
    ///         SellOnSeaport is intended to be deployed behind a proxy amd thus needs to initialize
    ///         its state outsize of a constructor.
    function initialize() public initializer {
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
        
        openseaZone = 0x004C00500000aD104D7DBd00e3ae0A5C00560C00;
        openseaFeeRecepient = 0x0000a26b00c1F0DF003000390027140000fAa719;
        openseaZoneHash = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        openseaConduitKey = bytes32(0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000);
        openseaConduit = 0x1E0049783F008A0085193E00003D00cd54003c71;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateLiquidityContractAddress(address newLiquidityContractAddress)
        external
        onlyOwner
    {
        require(address(newLiquidityContractAddress) != address(0), "00035");
        emit SellOnSeaportXLiquidityContractAddressUpdated(
            liquidityContractAddress,
            newLiquidityContractAddress
        );
        liquidityContractAddress = newLiquidityContractAddress;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateLendingContractAddress(address newLendingContractAddress) external onlyOwner {
        require(address(newLendingContractAddress) != address(0), "00035");
        emit SellOnSeaportXLendingContractAddressUpdated(
            lendingContractAddress,
            newLendingContractAddress
        );
        lendingContractAddress = newLendingContractAddress;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateSeaportContractAddress(address newSeaportContractAddress) external onlyOwner {
        require(address(newSeaportContractAddress) != address(0), "00035");
        emit SellOnSeaportXSeaportContractAddressUpdated(seaportContractAddress, newSeaportContractAddress);
        seaportContractAddress = newSeaportContractAddress;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateFlashSellContractAddress(address newFlashSellContractAddress) external onlyOwner {
        require(address(newFlashSellContractAddress) != address(0), "00035");
        emit SellOnSeaportXFlashSellContractAddressUpdated(flashSellContractAddress, newFlashSellContractAddress);
        flashSellContractAddress = newFlashSellContractAddress;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateWethContractAddress(address newWethContractAddress) external onlyOwner {
        require(address(newWethContractAddress) != address(0), "00035");
        emit SellOnSeaportXWethContractAddressUpdated(wethContractAddress, newWethContractAddress);
        wethContractAddress = newWethContractAddress;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateOpenseaZone(address newOpenseaZone) external onlyOwner {
        require(address(newOpenseaZone) != address(0), "00035");
        emit OpenseaZoneUpdated(openseaZone, newOpenseaZone);
        openseaZone = newOpenseaZone;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateOpenseaFeeRecepient(address newOpenseaFeeRecepient) external onlyOwner {
        require(address(newOpenseaFeeRecepient) != address(0), "00035");
        emit OpenseaFeeRecepientUpdated(openseaFeeRecepient, newOpenseaFeeRecepient);
        openseaFeeRecepient = newOpenseaFeeRecepient;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateOpenseaZoneHash(bytes32 newOpenseaZoneHash) external onlyOwner {
        emit OpenseaZoneHashUpdated(openseaZoneHash, newOpenseaZoneHash);
        openseaZoneHash = newOpenseaZoneHash;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateOpenseaConduitKey(bytes32 newOpenseaConduitKey) external onlyOwner {
        emit OpenseaConduitKeyUpdated(openseaConduitKey, newOpenseaConduitKey);
        openseaConduitKey = newOpenseaConduitKey;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateOpenseaConduit(address newOpenseaConduit) external onlyOwner {
        emit OpenseaConduitUpdated(openseaConduit, newOpenseaConduit);
        openseaConduit = newOpenseaConduit;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function pauseSanctions() external onlyOwner {
        _sanctionsPause = true;
        emit SellOnSeaportSanctionsPaused();
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function unpauseSanctions() external onlyOwner {
        _sanctionsPause = false;
        emit SellOnSeaportSanctionsUnpaused();
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc ISellOnSeaport
    function listNftForSale(
        address nftContractAddress,
        uint256 nftId,
        uint256 listingPrice,
        uint256 listingStartTime,
        uint256 listingEndTime,
        uint256 salt
    ) external whenNotPaused nonReentrant returns (bytes32) {
        LoanAuction memory loanAuction = ILending(lendingContractAddress).getLoanAuction(nftContractAddress, nftId); 
        uint256 openSeaFeeAmount = listingPrice - (listingPrice * 39) / 40;

        // validate inputs and its price wrt listingEndTime
        _requireNftOwner(loanAuction);
        _requireIsNotSanctioned(msg.sender);
        _requireOpenLoan(loanAuction);
        _requireListingValueGreaterThanLoanRepaymentAmountUntilListingExpiry(loanAuction, listingPrice, openSeaFeeAmount, listingEndTime);        
        
        // construct Seaport Order
        ISeaport.Order[] memory order  = _constructOrder(
            nftContractAddress,
            nftId,
            listingPrice,
            openSeaFeeAmount,
            listingStartTime,
            listingEndTime,
            loanAuction.asset,
            salt
        );
        // approve the NFT for Seaport address
        ILending(lendingContractAddress).approveNft(nftContractAddress, nftId, openseaConduit);
        // call lending contract to validate listing to Seaport
        ILending(lendingContractAddress).validateSeaportOrderSellOnSeaport(seaportContractAddress, order);
        // get orderHash by calling ISeaport.getOrderHash()
        bytes32 orderHash = _getOrderHash(order[0]);
        // validate order status by calling ISeaport.getOrderStatus(orderHash)
        (bool validated,,,) = ISeaport(seaportContractAddress).getOrderStatus(orderHash);
        require(validated, "00059");

        // store the listing with orderHash
        _orderHashToListing[orderHash] = SeaportListing(nftContractAddress, nftId, listingPrice - openSeaFeeAmount);

        // emit orderHash with it's listing
        emit ListedOnSeaport(nftContractAddress, nftId, orderHash, loanAuction);
        return orderHash;
    }

    /// @inheritdoc ISellOnSeaport
    function validateSaleAndWithdraw(
        address nftContractAddress,
        uint256 nftId,
        bytes32 orderHash
    ) external whenNotPaused nonReentrant {
        LoanAuction memory loanAuction = ILending(lendingContractAddress).getLoanAuction(nftContractAddress, nftId);

        SeaportListing memory listing = _requireValidOrderHash(nftContractAddress, nftId, orderHash);
        _requireLenderOrNftOwner(loanAuction);
        _requireIsNotSanctioned(msg.sender);
        _requireOpenLoan(loanAuction);
        
        // validate order status
        (bool valid, bool cancelled, uint256 filled, )  = ISeaport(seaportContractAddress).getOrderStatus(orderHash);
        require(valid, "00059");
        require(!cancelled, "00062");
        require(filled == 1, "00063");
        
        // close the loan and transfer remaining amount to the borrower
        uint256 totalLoanPaymentAmount = _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, block.timestamp);
        if (loanAuction.asset == ETH_ADDRESS) {
            // settle the loan
            ILending(lendingContractAddress).repayLoanForAccountInternal{value: totalLoanPaymentAmount}(
                nftContractAddress,
                nftId,
                loanAuction.loanBeginTimestamp
            );
            // transfer the remaining to the borrower
            payable(loanAuction.nftOwner).sendValue(listing.listingValue - totalLoanPaymentAmount);
        } else {
            // settle the loan
            IERC20Upgradeable assetToken = IERC20Upgradeable(loanAuction.asset);
            uint256 allowance = assetToken.allowance(address(this), liquidityContractAddress);
            if (allowance > 0) {
                assetToken.safeDecreaseAllowance(liquidityContractAddress, allowance);
            }
            assetToken.safeIncreaseAllowance(liquidityContractAddress, totalLoanPaymentAmount);
            ILending(lendingContractAddress).repayLoanForAccountInternal(
                nftContractAddress,
                nftId,
                loanAuction.loanBeginTimestamp
            );
            // transfer the remaining to the borrower
            IERC20Upgradeable(loanAuction.asset).safeTransfer(loanAuction.nftOwner, listing.listingValue - totalLoanPaymentAmount);
        }
    }

    function cancelNftListing(ISeaport.OrderComponents memory orderComponents) external whenNotPaused nonReentrant {
        bytes32 orderHash = ISeaport(seaportContractAddress).getOrderHash(orderComponents);
        address nftContractAddress = orderComponents.offer[0].token;
        uint256 nftId = orderComponents.offer[0].identifierOrCriteria;

        LoanAuction memory loanAuction = ILending(lendingContractAddress).getLoanAuction(nftContractAddress, nftId); 

        // validate inputs
        _requireNftOwner(loanAuction);
        _requireValidOrderHash(nftContractAddress, nftId, orderHash);
        _requireIsNotSanctioned(msg.sender);

        // validate order status
        (bool valid, bool cancelled, uint256 filled, )  = ISeaport(seaportContractAddress).getOrderStatus(orderHash);
        require(valid, "00059");
        require(!cancelled, "00062");
        require(filled == 0, "00063");
        
        ISeaport.OrderComponents[] memory orderComponentsList = new ISeaport.OrderComponents[](1);
        orderComponentsList[0] =  orderComponents;
        require(ILending(lendingContractAddress).cancelOrderSellOnSeaport(seaportContractAddress, orderComponentsList), "00065");

        // emit orderHash with it's listing
        emit ListingCancelledSeaport(nftContractAddress, nftId, orderHash, loanAuction);
    }

    function executeOperation(
        address nftContractAddress,
        uint256 nftId,
        address loanAsset,
        uint256 loanAmount,
        address initiator,
        bytes calldata data
    ) external payable returns (bool) {
        _requireFlashSellContract();

        // decode data
        (ISeaport.Order memory order, bytes32 fulfillerConduitKey) = abi.decode(data, (ISeaport.Order, bytes32));
        _requireValidOrderAsset(order, nftContractAddress, nftId, loanAsset);

        // approve the NFT for Seaport conduit
        IERC721Upgradeable(nftContractAddress).approve(seaportContractAddress, nftId);

        IERC20Upgradeable asset;
        if (loanAsset != address(0)) {
            asset = IERC20Upgradeable(loanAsset);
        } else {
            asset = IERC20Upgradeable(wethContractAddress);
        }

        uint256 assetBalanceBefore = _getAssetBalance(address(asset));
        
        uint256 allowance = asset.allowance(address(this), seaportContractAddress);
        if (allowance > 0) {
            asset.safeDecreaseAllowance(seaportContractAddress, allowance);
        }
        asset.safeIncreaseAllowance(seaportContractAddress, order.parameters.consideration[1].endAmount);

        require(
            ISeaport(seaportContractAddress).fulfillOrder(order, fulfillerConduitKey),
            "00048"
        );

        uint256 assetBalanceAfter = _getAssetBalance(address(asset));

        // require assets received are enough to settle the loan
        require(assetBalanceAfter - assetBalanceBefore >= loanAmount, "00066");

        if (loanAsset == address(0)) {
            // convert weth to eth
            (bool success,) = wethContractAddress.call(abi.encodeWithSignature("withdraw(uint256)", assetBalanceAfter - assetBalanceBefore));
            require(success, "00068");
            // transfer the asset to FlashSell to settle the loan
            payable(flashSellContractAddress).sendValue(loanAmount);
            // transfer the remaining to the initiator
            payable(initiator).sendValue(assetBalanceAfter - assetBalanceBefore - loanAmount);
        } else {
            // transfer the asset to FlashSell to settle the loan
            IERC20Upgradeable(loanAsset).safeTransfer(flashSellContractAddress, loanAmount);
            // transfer the remaining to the initiator
            IERC20Upgradeable(loanAsset).safeTransfer(initiator, assetBalanceAfter - assetBalanceBefore - loanAmount);
        }
        return true;
    }

    function _constructOrder(
        address nftContractAddress,
        uint256 nftId,
        uint256 listingPrice,
        uint256 openseaFeeAmount,
        uint256 listingStartTime,
        uint256 listingEndTime,
        address asset,
        uint256 randomSalt
    ) internal view returns (ISeaport.Order[] memory order) {
        ISeaport.ItemType considerationItemType = (asset == ETH_ADDRESS ? ISeaport.ItemType.NATIVE : ISeaport.ItemType.ERC20);
        address considerationToken = (asset == ETH_ADDRESS ? address(0) : asset);

        order = new ISeaport.Order[](1);
        order[0] = ISeaport.Order(
            {
                parameters: ISeaport.OrderParameters(
                    {
                        offerer: lendingContractAddress,
                        zone: openseaZone,
                        offer: new ISeaport.OfferItem[](1),
                        consideration: new ISeaport.ConsiderationItem[](2),
                        orderType: ISeaport.OrderType.FULL_OPEN,
                        startTime: listingStartTime,
                        endTime: listingEndTime,
                        zoneHash: openseaZoneHash,
                        salt: randomSalt,
                        conduitKey: openseaConduitKey,
                        totalOriginalConsiderationItems: 2
                    }
                ),
                signature: bytes("")
            }
        );
        order[0].parameters.offer[0] = ISeaport.OfferItem(
            {
                itemType: ISeaport.ItemType.ERC721,
                token: nftContractAddress,
                identifierOrCriteria: nftId,
                startAmount: 1,
                endAmount: 1
            }
        );
        order[0].parameters.consideration[0] = ISeaport.ConsiderationItem(
            {
                itemType: considerationItemType,
                token: considerationToken,
                identifierOrCriteria: 0,
                startAmount: listingPrice - openseaFeeAmount,
                endAmount:listingPrice - openseaFeeAmount,
                recipient: payable(address(this))
            }
            
        );
        order[0].parameters.consideration[1] = ISeaport.ConsiderationItem(
            {
                itemType: considerationItemType,
                token: considerationToken,
                identifierOrCriteria: 0,
                startAmount: openseaFeeAmount,
                endAmount: openseaFeeAmount,
                recipient: payable(openseaFeeRecepient)
            }
        );
    }

    function _requireListingValueGreaterThanLoanRepaymentAmountUntilListingExpiry(
        LoanAuction memory loanAuction,
        uint256 listingPrice,
        uint256 openseaFeeAmount,
        uint256 listingEndTime
    ) internal view {
        require(
            listingPrice - openseaFeeAmount >= _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, listingEndTime),
            "00060"
        );
    }

    function _requireValidOrderHash(
        address nftContractAddress,
        uint256 nftId,
        bytes32 orderHash
    ) internal view returns (SeaportListing memory listing){
        listing = _orderHashToListing[orderHash];
        require(listing.nftContractAddress == nftContractAddress && listing.nftId == nftId, "00064");
    }

    function _calculateTotalLoanPaymentAmountAtTimestamp(
        LoanAuction memory loanAuction,
        uint256 timestamp
        ) internal view returns(uint256) {

        uint256 timePassed = timestamp - loanAuction.lastUpdatedTimestamp;

        uint256 lenderInterest = (timePassed * loanAuction.interestRatePerSecond);
        uint256 protocolInterest = (timePassed * loanAuction.protocolInterestRatePerSecond);

        uint256 interestThreshold = (uint256(loanAuction.amountDrawn) * ILending(lendingContractAddress).gasGriefingPremiumBps()) /
            MAX_BPS;

        lenderInterest = lenderInterest > interestThreshold ? lenderInterest : interestThreshold;

        return loanAuction.accumulatedLenderInterest +
            loanAuction.accumulatedPaidProtocolInterest +
            loanAuction.unpaidProtocolInterest +
            loanAuction.slashableLenderInterest +
            loanAuction.amountDrawn +
            lenderInterest +
            protocolInterest;
    } 

    function _getOrderHash(ISeaport.Order memory order) internal view returns (bytes32 orderHash) {
        // Derive order hash by supplying order parameters along with counter.
        orderHash = ISeaport(seaportContractAddress).getOrderHash(
            ISeaport.OrderComponents(
                order.parameters.offerer,
                order.parameters.zone,
                order.parameters.offer,
                order.parameters.consideration,
                order.parameters.orderType,
                order.parameters.startTime,
                order.parameters.endTime,
                order.parameters.zoneHash,
                order.parameters.salt,
                order.parameters.conduitKey,
                ISeaport(seaportContractAddress).getCounter(order.parameters.offerer)
            )
        );
    }

    function _requireNftOwner(LoanAuction memory loanAuction)
        internal
        view
    {
        require(msg.sender == loanAuction.nftOwner, "00021");
    }

    function _requireLenderOrNftOwner(LoanAuction memory loanAuction)
        internal
        view
    {
        require(msg.sender == loanAuction.nftOwner || msg.sender == loanAuction.lender, "00061");
    }

    function _requireOpenLoan(LoanAuction memory loanAuction) internal pure {
        require(loanAuction.lastUpdatedTimestamp != 0, "00007");
    }

    function _requireIsNotSanctioned(address addressToCheck) internal view {
        if (!_sanctionsPause) {
            SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
            bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
            require(!isToSanctioned, "00017");
        }
    }

    function _requireValidOrderAsset(
        ISeaport.Order memory order,
        address nftContractAddress,
        uint256 nftId,
        address loanAsset
    ) internal view {
        require(order.parameters.consideration[0].itemType == ISeaport.ItemType.ERC721, "00067");
        require(order.parameters.consideration[0].token == nftContractAddress, "00067");
        require(order.parameters.consideration[0].identifierOrCriteria == nftId, "00067");
        require(order.parameters.offer[0].itemType == ISeaport.ItemType.ERC20, "00067");
        require(order.parameters.consideration[1].itemType == ISeaport.ItemType.ERC20, "00067");
        if (loanAsset == address(0)) {
            require(order.parameters.offer[0].token == wethContractAddress,  "00067");
            require(order.parameters.consideration[1].token == wethContractAddress,  "00067");
        } else {
            require(order.parameters.offer[0].token == loanAsset,  "00067");
            require(order.parameters.consideration[1].token == loanAsset,  "00067");
        }
    }

    function _getAssetBalance(address asset) internal view returns(uint256) {
        if (asset == address(0)) {
            return address(this).balance;
        } else {
            return IERC20Upgradeable(asset).balanceOf(address(this));
        }   
    }

    function _requireFlashSellContract() internal view {
        require(msg.sender == flashSellContractAddress, "00031");
    }

    /// @notice This contract needs to accept ETH from Seaport
    receive() external payable {}
}
