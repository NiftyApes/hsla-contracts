//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interfaces/niftyapes/lending/ILending.sol";
import "./interfaces/sanctions/SanctionsList.sol";
import "./interfaces/niftyapes/flashSell/IFlashSell.sol";
import "./flashSell/interfaces/IFlashSellReceiver.sol";

/// @notice Extension of NiftApes lending contract to allow for flash sale of NFTs
/// @title NiftyApesFlashSell
/// @custom:version 1.0
/// @author zishansami102 (zishansami.eth)
/// @custom:contributor captnseagraves (captnseagraves.eth)
contract NiftyApesFlashSell is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IFlashSell
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev Internal address used for for ETH in our mappings
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Internal constant address for the Chainalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    /// @inheritdoc IFlashSell
    address public lendingContractAddress;

    /// @inheritdoc IFlashSell
    address public liquidityContractAddress;

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
    }

    /// @inheritdoc IFlashSellAdmin
    function updateLendingContractAddress(address newLendingContractAddress) external onlyOwner {
        require(address(newLendingContractAddress) != address(0), "00035");
        emit FlashSellXLendingContractAddressUpdated(
            lendingContractAddress,
            newLendingContractAddress
        );
        lendingContractAddress = newLendingContractAddress;
    }

    /// @inheritdoc IFlashSellAdmin
    function updateLiquidityContractAddress(address newLiquidityContractAddress)
        external
        onlyOwner
    {
        require(address(newLiquidityContractAddress) != address(0), "00035");
        emit FlashSellXLiquidityContractAddressUpdated(
            liquidityContractAddress,
            newLiquidityContractAddress
        );
        liquidityContractAddress = newLiquidityContractAddress;
    }

    /// @inheritdoc IFlashSellAdmin
    function pauseSanctions() external onlyOwner {
        _sanctionsPause = true;
        emit FlashSellSanctionsPaused();
    }

    /// @inheritdoc IFlashSellAdmin
    function unpauseSanctions() external onlyOwner {
        _sanctionsPause = false;
        emit FlashSellSanctionsUnpaused();
    }

    /// @inheritdoc IFlashSellAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IFlashSellAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IFlashSell
    function borrowNFTForSale(
        address nftContractAddress,
        uint256 nftId,
        address receiver,
        bytes calldata data
    ) external whenNotPaused nonReentrant {
        address nftOwner = _requireNftOwner(nftContractAddress, nftId);
        _requireIsNotSanctioned(msg.sender);
        _requireIsNotSanctioned(nftOwner);

        LoanAuction memory loanAuction = ILending(lendingContractAddress).getLoanAuction(
            nftContractAddress,
            nftId
        );

        // transfer NFT
        ILending(lendingContractAddress).transferNft(nftContractAddress, nftId, receiver);

        address loanAsset;
        if (loanAuction.asset != ETH_ADDRESS) {
            loanAsset = loanAuction.asset;
        }
        uint256 totalLoanPaymentAmount = _calculateTotalLoanPaymentAmount(
            loanAuction,
            nftContractAddress,
            nftId
        );

        uint256 assetBalanceBefore = _getAssetBalance(loanAuction.asset);
        _ethTransferable = true;
        // execute firewalled external arbitrary functionality
        // function must send correct funds required to close the loan
        require(
            IFlashSellReceiver(receiver).executeOperation(
                nftContractAddress,
                nftId,
                loanAsset,
                totalLoanPaymentAmount,
                msg.sender,
                data
            ),
            "00052"
        );
        _ethTransferable = false;
        uint256 assetBalanceAfter = _getAssetBalance(loanAuction.asset);

        // Check assets amount recieved is equal to total loan amount required to close the loan
        _requireCorrectFundsSent(assetBalanceAfter - assetBalanceBefore, totalLoanPaymentAmount);

        if (loanAuction.asset == ETH_ADDRESS) {
            ILending(lendingContractAddress).repayLoanForAccountInternal{value: totalLoanPaymentAmount}(
                nftContractAddress,
                nftId,
                loanAuction.loanBeginTimestamp
            );
        } else {
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
        }
        // emit event
        emit FlashSell(nftContractAddress, nftId, receiver);
    }

    function _requireEthTransferable() internal view {
        require(_ethTransferable, "00043");
    }

    function _requireNftOwner(address nftContractAddress, uint256 nftId)
        internal
        view
        returns (address nftOwner)
    {
        nftOwner = ILending(lendingContractAddress).ownerOf(nftContractAddress, nftId);
        require(nftOwner == msg.sender, "00021");
    }

    function _requireCorrectFundsSent(uint256 balanceReceived, uint256 balanceRequired)
        internal
        pure
    {
        require(balanceReceived == balanceRequired, "00057");
    }

    function _requireIsNotSanctioned(address addressToCheck) internal view {
        if (!_sanctionsPause) {
            SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
            bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
            require(!isToSanctioned, "00017");
        }
    }

    function _calculateTotalLoanPaymentAmount(
        LoanAuction memory loanAuction,
        address nftContractAddress,
        uint256 nftId
    ) internal view returns (uint256) {
        uint256 interestThresholdDelta;

        if (loanAuction.loanEndTimestamp - 1 days > uint32(block.timestamp)) {
            interestThresholdDelta = ILending(lendingContractAddress)
                .checkSufficientInterestAccumulated(nftContractAddress, nftId);
        }

        (uint256 lenderInterest, uint256 protocolInterest) = ILending(lendingContractAddress)
            .calculateInterestAccrued(nftContractAddress, nftId);

        return
            uint256(loanAuction.accumulatedLenderInterest) +
            loanAuction.accumulatedPaidProtocolInterest +
            loanAuction.unpaidProtocolInterest +
            loanAuction.slashableLenderInterest +
            loanAuction.amountDrawn +
            interestThresholdDelta +
            lenderInterest +
            protocolInterest;
    }

    function _getAssetBalance(address asset) internal view returns (uint256) {
        if (asset == ETH_ADDRESS) {
            return address(this).balance;
        } else {
            return IERC20Upgradeable(asset).balanceOf(address(this));
        }
    }

    receive() external payable {
        _requireEthTransferable();
    }
}
