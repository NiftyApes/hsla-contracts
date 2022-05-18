//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "./interfaces/compound/ICEther.sol";
import "./interfaces/compound/ICERC20.sol";
import "./interfaces/niftyapes/INiftyApes.sol";
import "./interfaces/niftyapes/offers/IOffers.sol";
import "./interfaces/sanctions/SanctionsList.sol";
import "./lib/ECDSABridge.sol";
import "./lib/Math.sol";

// import "./test/Console.sol";

/// @title Implemention of the INiftyApes interface
contract NiftyApesLiquidity is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ILiquidity
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    /// @dev Internal address used for for ETH in our mappings
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Internal constant address for the Chinalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    /// @inheritdoc ILiquidity
    mapping(address => address) public override assetToCAsset;

    /// @notice The reverse mapping for assetToCAsset
    mapping(address => address) internal _cAssetToAsset;

    /// @notice The account balance for each asset of a user
    mapping(address => mapping(address => Balance)) internal _balanceByAccountByAsset;

    /// @inheritdoc ILiquidity
    mapping(address => uint256) public override maxBalanceByCAsset;

    /// @inheritdoc ILending
    uint96 public protocolInterestBps;

    /// @inheritdoc ILending
    uint16 public refinancePremiumLenderBps;

    /// @inheritdoc ILending
    uint16 public refinancePremiumProtocolBps;

    /// @inheritdoc ILending
    uint16 public regenCollectiveBpsOfRevenue;

    /// @dev @inheritdoc ILending
    address public regenCollectiveAddress;

    /// @notice A bool to prevent external eth from being received and locked in the contract
    bool private _ethTransferable = false;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting storage.
    uint256[500] private __gap;

    /// @notice The initializer for the NiftyApes protocol.
    ///         Nifty Apes is intended to be deployed behind a proxy amd thus needs to initialize
    ///         its state outsize of a constructor.
    function initialize() public initializer {
        regenCollectiveBpsOfRevenue = 100;
        regenCollectiveAddress = address(0x252de94Ae0F07fb19112297F299f8c9Cc10E28a6);

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    }

    /// @inheritdoc INiftyApesAdmin
    function setCAssetAddress(address asset, address cAsset) external onlyOwner {
        assetToCAsset[asset] = cAsset;
        _cAssetToAsset[cAsset] = asset;

        emit NewAssetListed(asset, cAsset);
    }

    /// @inheritdoc INiftyApesAdmin
    function setMaxCAssetBalance(address asset, uint256 maxBalance) external onlyOwner {
        maxBalanceByCAsset[getCAsset(asset)] = maxBalance;
    }

    /// @inheritdoc INiftyApesAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc INiftyApesAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc ILiquidity
    function getCAssetBalance(address account, address cAsset) public view returns (uint256) {
        return _balanceByAccountByAsset[account][cAsset].cAssetBalance;
    }

    /// @inheritdoc ILiquidity
    function supplyErc20(address asset, uint256 tokenAmount)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cAsset = getCAsset(asset);

        requireIsNotSanctioned(msg.sender);

        uint256 cTokensMinted = mintCErc20(msg.sender, address(this), asset, tokenAmount);

        _balanceByAccountByAsset[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        requireMaxCAssetBalance(cAsset);

        emit Erc20Supplied(msg.sender, asset, tokenAmount, cTokensMinted);

        return cTokensMinted;
    }

    /// @inheritdoc ILiquidity
    function supplyCErc20(address cAsset, uint256 cTokenAmount)
        external
        whenNotPaused
        nonReentrant
    {
        getAsset(cAsset); // Ensures asset / cAsset is in the allow list
        IERC20Upgradeable cToken = IERC20Upgradeable(cAsset);

        requireIsNotSanctioned(msg.sender);

        cToken.safeTransferFrom(msg.sender, address(this), cTokenAmount);

        _balanceByAccountByAsset[msg.sender][cAsset].cAssetBalance += cTokenAmount;

        requireMaxCAssetBalance(cAsset);

        emit CErc20Supplied(msg.sender, cAsset, cTokenAmount);
    }

    /// @inheritdoc ILiquidity
    function withdrawErc20(address asset, uint256 tokenAmount)
        public
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cAsset = getCAsset(asset);
        IERC20Upgradeable underlying = IERC20Upgradeable(asset);

        if (msg.sender == owner()) {
            uint256 cTokensBurnt = ownerWithdraw(asset, cAsset);
            return cTokensBurnt;
        } else {
            uint256 cTokensBurnt = burnCErc20(asset, tokenAmount);

            withdrawCBalance(msg.sender, cAsset, cTokensBurnt);

            underlying.safeTransfer(msg.sender, tokenAmount);

            emit Erc20Withdrawn(msg.sender, asset, tokenAmount, cTokensBurnt);

            return cTokensBurnt;
        }
    }

    /// @inheritdoc ILiquidity
    function withdrawCErc20(address cAsset, uint256 cTokenAmount)
        external
        whenNotPaused
        nonReentrant
    {
        // Making sure a mapping for cAsset exists
        getAsset(cAsset);
        IERC20Upgradeable cToken = IERC20Upgradeable(cAsset);

        withdrawCBalance(msg.sender, cAsset, cTokenAmount);

        cToken.safeTransfer(msg.sender, cTokenAmount);

        emit CErc20Withdrawn(msg.sender, cAsset, cTokenAmount);
    }

    /// @inheritdoc ILiquidity
    function supplyEth() external payable whenNotPaused nonReentrant returns (uint256) {
        address cAsset = getCAsset(ETH_ADDRESS);

        requireIsNotSanctioned(msg.sender);

        uint256 cTokensMinted = mintCEth(msg.value);

        _balanceByAccountByAsset[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        requireMaxCAssetBalance(cAsset);

        emit EthSupplied(msg.sender, msg.value, cTokensMinted);

        return cTokensMinted;
    }

    /// @inheritdoc ILiquidity
    function withdrawEth(uint256 amount) external whenNotPaused nonReentrant returns (uint256) {
        address cAsset = getCAsset(ETH_ADDRESS);

        uint256 cTokensBurnt = burnCErc20(ETH_ADDRESS, amount);

        withdrawCBalance(msg.sender, cAsset, cTokensBurnt);

        payable(msg.sender).sendValue(amount);

        emit EthWithdrawn(msg.sender, amount, cTokensBurnt);

        return cTokensBurnt;
    }

    function ownerWithdraw(address asset, address cAsset) internal returns (uint256 cTokensBurnt) {
        IERC20Upgradeable underlying = IERC20Upgradeable(asset);
        uint256 ownerBalance = getCAssetBalance(owner(), cAsset);

        uint256 ownerBalanceUnderlying = cAssetAmountToAssetAmount(cAsset, ownerBalance);

        cTokensBurnt = burnCErc20(asset, ownerBalanceUnderlying);

        uint256 bpsForRegen = (cTokensBurnt * regenCollectiveBpsOfRevenue) / MAX_BPS;

        uint256 ownerBalanceMinusRegen = cTokensBurnt - bpsForRegen;

        uint256 ownerAmountUnderlying = cAssetAmountToAssetAmount(cAsset, ownerBalanceMinusRegen);

        uint256 regenAmountUnderlying = cAssetAmountToAssetAmount(cAsset, bpsForRegen);

        withdrawCBalance(owner(), cAsset, cTokensBurnt);

        underlying.safeTransfer(owner(), ownerAmountUnderlying);

        underlying.safeTransfer(regenCollectiveAddress, regenAmountUnderlying);

        emit PercentForRegen(regenCollectiveAddress, asset, regenAmountUnderlying, bpsForRegen);

        emit Erc20Withdrawn(owner(), asset, ownerAmountUnderlying, ownerBalanceMinusRegen);
    }

    /// @dev Struct exists since we ran out of stack space in _repayLoan
    struct RepayLoanStruct {
        address nftContractAddress;
        uint256 nftId;
        bool repayFull;
        uint256 paymentAmount;
        bool checkMsgSender;
    }



    function handleLoanPayment(
        RepayLoanStruct memory rls,
        LoanAuction storage loanAuction,
        uint256 payment
    ) internal returns (uint256) {
        if (loanAuction.asset == ETH_ADDRESS) {
            if (rls.repayFull) {
                require(msg.value >= payment, "msg.value too low");
            }

            uint256 cTokensMinted = mintCEth(payment);

            // If the caller has overpaid we send the extra ETH back
            if (payment < msg.value) {
                payable(msg.sender).sendValue(msg.value - payment);
            }
            return cTokensMinted;
        } else {
            return mintCErc20(msg.sender, address(this), loanAuction.asset, payment);
        }
    }

    function slashUnsupportedAmount(
        LoanAuction storage loanAuction,
        uint256 drawAmount,
        address cAsset
    ) internal returns (uint256) {
        uint256 lenderBalance = getCAssetBalance(loanAuction.lender, cAsset);
        uint256 drawTokens = assetAmountToCAssetAmount(loanAuction.asset, drawAmount);

        if (lenderBalance < drawTokens) {
            uint256 balanceDelta = drawTokens - lenderBalance;

            uint256 balanceDeltaUnderlying = cAssetAmountToAssetAmount(cAsset, balanceDelta);
            loanAuction.amountDrawn -= SafeCastUpgradeable.toUint128(balanceDeltaUnderlying);

            uint256 lenderBalanceUnderlying = cAssetAmountToAssetAmount(cAsset, lenderBalance);
            drawAmount = lenderBalanceUnderlying;
        }

        return drawAmount;
    }

    /// @inheritdoc INiftyApesAdmin
    function updateRegenCollectiveBpsOfRevenue(uint16 newRegenCollectiveBpsOfRevenue)
        external
        onlyOwner
    {
        require(newRegenCollectiveBpsOfRevenue <= MAX_FEE, "max fee");
        require(newRegenCollectiveBpsOfRevenue >= regenCollectiveBpsOfRevenue, "must be greater");
        emit RegenCollectiveBpsOfRevenueUpdated(
            regenCollectiveBpsOfRevenue,
            newRegenCollectiveBpsOfRevenue
        );
        regenCollectiveBpsOfRevenue = newRegenCollectiveBpsOfRevenue;
    }

    /// @inheritdoc INiftyApesAdmin
    function updateRegenCollectiveAddress(address newRegenCollectiveAddress) external onlyOwner {
        emit RegenCollectiveAddressUpdated(newRegenCollectiveAddress);
        regenCollectiveAddress = newRegenCollectiveAddress;
    }

    function requireEthTransferable() internal view {
        require(_ethTransferable, "eth not transferable");
    }

    function requireSignature65(bytes memory signature) internal pure {
        require(signature.length == 65, "signature unsupported");
    }

    function requireOfferPresent(Offer memory offer) internal pure {
        require(offer.asset != address(0), "no offer");
    }

    function requireOfferAmount(Offer memory offer, uint256 amount) internal pure {
        require(offer.amount >= amount, "offer amount");
    }

    function requireNoOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.lastUpdatedTimestamp == 0, "Loan already open");
    }

    function requireOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.lastUpdatedTimestamp != 0, "loan not active");
    }

    function requireLoanExpired(LoanAuction storage loanAuction) internal view {
        require(currentTimestamp() >= loanAuction.loanEndTimestamp, "loan not expired");
    }

    function requireLoanNotExpired(LoanAuction storage loanAuction) internal view {
        require(currentTimestamp() < loanAuction.loanEndTimestamp, "loan expired");
    }

    function requireOfferNotExpired(Offer memory offer) internal view {
        require(offer.expiration > currentTimestamp(), "offer expired");
    }

    function requireMinDurationForOffer(Offer memory offer) internal pure {
        require(offer.duration >= 1 days, "offer duration");
    }

    function requireLenderOffer(Offer memory offer) internal pure {
        require(offer.lenderOffer, "lender offer");
    }

    function requireBorrowerOffer(Offer memory offer) internal pure {
        require(!offer.lenderOffer, "borrower offer");
    }

    function requireNoFloorTerms(Offer memory offer) internal pure {
        require(!offer.floorTerm, "floor term");
    }

    function requireNoFixedTerm(LoanAuction storage loanAuction) internal view {
        require(!loanAuction.fixedTerms, "fixed term loan");
    }

    function requireNoFixTermOffer(Offer memory offer) internal pure {
        require(!offer.fixedTerms, "fixed term offer");
    }

    function requireIsNotSanctioned(address addressToCheck) internal view {
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

    function requireLender(address lender) internal view {
        require(lender == msg.sender, "lender");
    }

    function requireMatchingAsset(address asset1, address asset2) internal pure {
        require(asset1 == asset2, "asset mismatch");
    }

    function requireFundsAvailable(LoanAuction storage loanAuction, uint256 drawAmount)
        internal
        view
    {
        require((drawAmount + loanAuction.amountDrawn) <= loanAuction.amount, "funds overdrawn");
    }

    function requireNftOwner(LoanAuction storage loanAuction, address nftOwner) internal view {
        require(nftOwner == loanAuction.nftOwner, "nft owner");
    }

    function requireMatchingNftId(Offer memory offer, uint256 nftId) internal pure {
        require(nftId == offer.nftId, "offer nftId mismatch");
    }

    function requireMsgValue(uint256 amount) internal view {
        require(amount == msg.value, "msg value");
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

    function requireOfferParity(LoanAuction storage loanAuction, Offer memory offer) internal view {
        // Caching fields here for gas usage
        uint256 amount = loanAuction.amount;
        uint256 interestRatePerSecond = loanAuction.interestRatePerSecond;
        uint256 loanEndTime = loanAuction.loanEndTimestamp;
        uint256 offerEndTime = loanAuction.loanBeginTimestamp + offer.duration;

        // Better amount
        if (
            offer.amount > amount &&
            offer.interestRatePerSecond <= interestRatePerSecond &&
            offerEndTime >= loanEndTime
        ) {
            return;
        }

        // Lower interest rate
        if (
            offer.amount >= amount &&
            offer.interestRatePerSecond < interestRatePerSecond &&
            offerEndTime >= loanEndTime
        ) {
            return;
        }

        // Longer duration
        if (
            offer.amount >= amount &&
            offer.interestRatePerSecond <= interestRatePerSecond &&
            offerEndTime > loanEndTime
        ) {
            return;
        }

        revert("not an improvement");
    }

    function createLoan(
        LoanAuction storage loanAuction,
        Offer memory offer,
        address lender,
        address borrower
    ) internal {
        loanAuction.nftOwner = borrower;
        loanAuction.lender = lender;
        loanAuction.asset = offer.asset;
        loanAuction.amount = offer.amount;
        loanAuction.loanEndTimestamp = currentTimestamp() + offer.duration;
        loanAuction.loanBeginTimestamp = currentTimestamp();
        loanAuction.lastUpdatedTimestamp = currentTimestamp();
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;
        loanAuction.interestRatePerSecond = offer.interestRatePerSecond;

        uint96 protocolInterestRatePerSecond = calculateProtocolInterestPerSecond(
            offer.amount,
            offer.duration
        );

        loanAuction.protocolInterestRatePerSecond = protocolInterestRatePerSecond;
    }

    function transferNft(
        address nftContractAddress,
        uint256 nftId,
        address from,
        address to
    ) internal {
        IERC721Upgradeable(nftContractAddress).safeTransferFrom(from, to, nftId);
    }

    function sendValue(
        address asset,
        uint256 amount,
        address to
    ) internal {
        if (asset == ETH_ADDRESS) {
            payable(to).sendValue(amount);
        } else {
            IERC20Upgradeable(asset).safeTransfer(to, amount);
        }
    }

    function payoutCTokenBalances(
        LoanAuction storage loanAuction,
        address cAsset,
        uint256 totalCTokens,
        uint256 totalPayment
    ) internal {
        uint256 cTokensToLender = (totalCTokens *
            (loanAuction.amountDrawn + loanAuction.accumulatedLenderInterest)) / totalPayment;
        uint256 cTokensToProtocol = (totalCTokens * loanAuction.accumulatedProtocolInterest) /
            totalPayment;

        _balanceByAccountByAsset[loanAuction.lender][cAsset].cAssetBalance += cTokensToLender;
        _balanceByAccountByAsset[owner()][cAsset].cAssetBalance += cTokensToProtocol;
    }

    function currentTimestamp() internal view returns (uint32) {
        return SafeCastUpgradeable.toUint32(block.timestamp);
    }

    // This is needed to receive ETH when calling withdrawing ETH from compund
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {
        require(_ethTransferable, "eth not transferable");
    }

    function requireMaxCAssetBalance(address cAsset) internal view {
        uint256 maxCAssetBalance = maxBalanceByCAsset[cAsset];
        if (maxCAssetBalance != 0) {
            require(maxCAssetBalance >= ICERC20(cAsset).balanceOf(address(this)), "max casset");
        }
    }

    function mintCErc20(
        address from,
        address to,
        address asset,
        uint256 amount
    ) internal returns (uint256) {
        address cAsset = assetToCAsset[asset];
        IERC20Upgradeable underlying = IERC20Upgradeable(asset);
        ICERC20 cToken = ICERC20(cAsset);

        underlying.safeTransferFrom(from, to, amount);
        underlying.safeIncreaseAllowance(cAsset, amount);

        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        require(cToken.mint(amount) == 0, "cToken mint");
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceAfter - cTokenBalanceBefore;
    }

    function mintCEth(uint256 amount) internal returns (uint256) {
        address cAsset = assetToCAsset[ETH_ADDRESS];
        ICEther cToken = ICEther(cAsset);
        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        cToken.mint{ value: amount }();
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceAfter - cTokenBalanceBefore;
    }

    // @notice param amount is demoninated in the underlying asset, not cAsset
    function burnCErc20(address asset, uint256 amount) internal returns (uint256) {
        address cAsset = assetToCAsset[asset];
        ICERC20 cToken = ICERC20(cAsset);

        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        _ethTransferable = true;
        require(cToken.redeemUnderlying(amount) == 0, "redeemUnderlying failed");
        _ethTransferable = false;
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceBefore - cTokenBalanceAfter;
    }

    /// @inheritdoc ILiquidity
    function assetAmountToCAssetAmount(address asset, uint256 amount) public returns (uint256) {
        address cAsset = assetToCAsset[asset];
        ICERC20 cToken = ICERC20(cAsset);

        uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();
        return Math.divScalarByExpTruncate(amount, exchangeRateMantissa);
    }

    function cAssetAmountToAssetAmount(address cAsset, uint256 amount) internal returns (uint256) {
        ICERC20 cToken = ICERC20(cAsset);

        uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();
        return Math.mulScalarTruncate(amount, exchangeRateMantissa);
    }

    function getCAsset(address asset) public view returns (address) {
        address cAsset = assetToCAsset[asset];
        require(cAsset != address(0), "asset allow list");
        require(asset == _cAssetToAsset[cAsset], "non matching allow list");
        return cAsset;
    }

    function getAsset(address cAsset) internal view returns (address) {
        address asset = _cAssetToAsset[cAsset];
        require(asset != address(0), "cAsset allow list");
        require(cAsset == assetToCAsset[asset], "non matching allow list");
        return asset;
    }

    function withdrawCBalance(
        address account,
        address cAsset,
        uint256 cTokenAmount
    ) internal {
        requireCAssetBalance(account, cAsset, cTokenAmount);
        _balanceByAccountByAsset[account][cAsset].cAssetBalance -= cTokenAmount;
    }

    function renounceOwnership() public override onlyOwner {}
}
