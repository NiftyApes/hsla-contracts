//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "./interfaces/niftyapes/sellOnSeaport/ISellOnSeaport.sol";
import "./interfaces/niftyapes/lending/ILending.sol";
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./interfaces/sanctions/SanctionsList.sol";

/// @notice Extension of NiftApes lending contract to allow sale of NFTs on Seaport for closure of loans
/// @title SellOnSeaport
/// @custom:version 1.0
/// @author zishansami102 (zishansami.eth)
contract NiftyApesSellOnSeaport is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ISellOnSeaport
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
    address public openSeaZone;

    /// @inheritdoc ISellOnSeaport
    address public openSeaFeeRecepient;

    /// @inheritdoc ISellOnSeaport
    bytes32 public openSeaZoneHash;

    /// @inheritdoc ISellOnSeaport
    bytes32 public openSeaConduitKey;

    /// @inheritdoc ISellOnSeaport
    address public openSeaConduit;

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
        
        openSeaZone = 0x004C00500000aD104D7DBd00e3ae0A5C00560C00;
        openSeaFeeRecepient = 0x0000a26b00c1F0DF003000390027140000fAa719;
        openSeaZoneHash = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        openSeaConduitKey = bytes32(0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000);
        openSeaConduit = 0x1E0049783F008A0085193E00003D00cd54003c71;
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
    function updateOpenSeaZone(address newOpenSeaZone) external onlyOwner {
        require(address(newOpenSeaZone) != address(0), "00035");
        emit OpenSeaZoneUpdated(openSeaZone, newOpenSeaZone);
        openSeaZone = newOpenSeaZone;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateOpenSeaFeeRecepient(address newOpenSeaFeeRecepient) external onlyOwner {
        require(address(newOpenSeaFeeRecepient) != address(0), "00035");
        emit OpenSeaFeeRecepientUpdated(openSeaFeeRecepient, newOpenSeaFeeRecepient);
        openSeaFeeRecepient = newOpenSeaFeeRecepient;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateOpenSeaZoneHash(bytes32 newOpenSeaZoneHash) external onlyOwner {
        emit OpenSeaZoneHashUpdated(openSeaZoneHash, newOpenSeaZoneHash);
        openSeaZoneHash = newOpenSeaZoneHash;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateOpenSeaConduitKey(bytes32 newOpenSeaConduitKey) external onlyOwner {
        emit OpenSeaConduitKeyUpdated(openSeaConduitKey, newOpenSeaConduitKey);
        openSeaConduitKey = newOpenSeaConduitKey;
    }

    /// @inheritdoc ISellOnSeaportAdmin
    function updateOpenSeaConduit(address newOpenSeaConduit) external onlyOwner {
        emit OpenSeaConduitUpdated(openSeaConduit, newOpenSeaConduit);
        openSeaConduit = newOpenSeaConduit;
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
        ILending(lendingContractAddress).approveNft(nftContractAddress, nftId, openSeaConduit);
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

    function _constructOrder(
        address nftContractAddress,
        uint256 nftId,
        uint256 listingPrice,
        uint256 openSeaFeeAmount,
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
                        zone: openSeaZone,
                        offer: new ISeaport.OfferItem[](1),
                        consideration: new ISeaport.ConsiderationItem[](2),
                        orderType: ISeaport.OrderType.FULL_OPEN,
                        startTime: listingStartTime,
                        endTime: listingEndTime,
                        zoneHash: openSeaZoneHash,
                        salt: randomSalt,
                        conduitKey: openSeaConduitKey,
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
                startAmount: listingPrice - openSeaFeeAmount,
                endAmount:listingPrice - openSeaFeeAmount,
                recipient: payable(address(this))
            }
            
        );
        order[0].parameters.consideration[1] = ISeaport.ConsiderationItem(
            {
                itemType: considerationItemType,
                token: considerationToken,
                identifierOrCriteria: 0,
                startAmount: openSeaFeeAmount,
                endAmount: openSeaFeeAmount,
                recipient: payable(openSeaFeeRecepient)
            }
        );
    }

    function _requireListingValueGreaterThanLoanRepaymentAmountUntilListingExpiry(
        LoanAuction memory loanAuction,
        uint256 listingPrice,
        uint256 openSeaFeeAmount,
        uint256 listingEndTime
    ) internal view {
        require(
            listingPrice - openSeaFeeAmount >= _calculateTotalLoanPaymentAmountAtTimestamp(loanAuction, listingEndTime),
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

        uint256 interestThreshold;
        if (loanAuction.loanEndTimestamp - 1 days > uint32(timestamp)) {
            interestThreshold = (uint256(loanAuction.amountDrawn) * ILending(lendingContractAddress).gasGriefingPremiumBps()) /
                MAX_BPS;
        }

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

    /// @notice This contract needs to accept ETH from Seaport
    receive() external payable {}
}
