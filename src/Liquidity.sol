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
import "./interfaces/niftyapes/liquidity/ILiquidity.sol";
import "./interfaces/niftyapes/lending/ILending.sol";
import "./interfaces/niftyapes/offers/IOffers.sol";
import "./interfaces/sanctions/SanctionsList.sol";
import "./lib/ECDSABridge.sol";
import "./lib/Math.sol";

import "./test/Console.sol";

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

    address public lendingContractAddress;

    /// @inheritdoc ILiquidity
    uint16 public regenCollectiveBpsOfRevenue;

    /// @dev @inheritdoc ILiquidity
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

    /// @inheritdoc ILiquidityAdmin
    function setCAssetAddress(address asset, address cAsset) external onlyOwner {
        assetToCAsset[asset] = cAsset;
        _cAssetToAsset[cAsset] = asset;

        emit NewAssetListed(asset, cAsset);
    }

    /// @inheritdoc ILiquidityAdmin
    function setMaxCAssetBalance(address asset, uint256 maxBalance) external onlyOwner {
        maxBalanceByCAsset[getCAsset(asset)] = maxBalance;
    }

    /// @inheritdoc ILiquidityAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc ILiquidityAdmin
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

        uint256 cTokensMinted = _mintCErc20(msg.sender, address(this), asset, tokenAmount);

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
            uint256 cTokensBurnt = _burnCErc20(asset, tokenAmount);

            _withdrawCBalance(msg.sender, cAsset, cTokensBurnt);

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

        _withdrawCBalance(msg.sender, cAsset, cTokenAmount);

        cToken.safeTransfer(msg.sender, cTokenAmount);

        emit CErc20Withdrawn(msg.sender, cAsset, cTokenAmount);
    }

    /// @inheritdoc ILiquidity
    function supplyEth() external payable whenNotPaused nonReentrant returns (uint256) {
        address cAsset = getCAsset(ETH_ADDRESS);

        requireIsNotSanctioned(msg.sender);

        uint256 cTokensMinted = _mintCEth(msg.value);

        _balanceByAccountByAsset[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        requireMaxCAssetBalance(cAsset);

        emit EthSupplied(msg.sender, msg.value, cTokensMinted);

        return cTokensMinted;
    }

    /// @inheritdoc ILiquidity
    function withdrawEth(uint256 amount) external whenNotPaused nonReentrant returns (uint256) {
        address cAsset = getCAsset(ETH_ADDRESS);

        uint256 cTokensBurnt = _burnCErc20(ETH_ADDRESS, amount);

        _withdrawCBalance(msg.sender, cAsset, cTokensBurnt);

        payable(msg.sender).sendValue(amount);

        emit EthWithdrawn(msg.sender, amount, cTokensBurnt);

        return cTokensBurnt;
    }

    function ownerWithdraw(address asset, address cAsset) internal returns (uint256 cTokensBurnt) {
        IERC20Upgradeable underlying = IERC20Upgradeable(asset);
        uint256 ownerBalance = getCAssetBalance(owner(), cAsset);

        uint256 ownerBalanceUnderlying = cAssetAmountToAssetAmount(cAsset, ownerBalance);

        cTokensBurnt = _burnCErc20(asset, ownerBalanceUnderlying);

        uint256 bpsForRegen = (cTokensBurnt * regenCollectiveBpsOfRevenue) / 10_000;

        uint256 ownerBalanceMinusRegen = cTokensBurnt - bpsForRegen;

        uint256 ownerAmountUnderlying = cAssetAmountToAssetAmount(cAsset, ownerBalanceMinusRegen);

        uint256 regenAmountUnderlying = cAssetAmountToAssetAmount(cAsset, bpsForRegen);

        _withdrawCBalance(owner(), cAsset, cTokensBurnt);

        underlying.safeTransfer(owner(), ownerAmountUnderlying);

        underlying.safeTransfer(regenCollectiveAddress, regenAmountUnderlying);

        emit PercentForRegen(regenCollectiveAddress, asset, regenAmountUnderlying, bpsForRegen);

        emit Erc20Withdrawn(owner(), asset, ownerAmountUnderlying, ownerBalanceMinusRegen);
    }

    /// @inheritdoc ILiquidityAdmin
    function updateRegenCollectiveBpsOfRevenue(uint16 newRegenCollectiveBpsOfRevenue)
        external
        onlyOwner
    {
        require(newRegenCollectiveBpsOfRevenue <= 1_000, "max fee");
        require(newRegenCollectiveBpsOfRevenue >= regenCollectiveBpsOfRevenue, "must be greater");
        emit RegenCollectiveBpsOfRevenueUpdated(
            regenCollectiveBpsOfRevenue,
            newRegenCollectiveBpsOfRevenue
        );
        regenCollectiveBpsOfRevenue = newRegenCollectiveBpsOfRevenue;
    }

    /// @inheritdoc ILiquidityAdmin
    function updateRegenCollectiveAddress(address newRegenCollectiveAddress) external onlyOwner {
        emit RegenCollectiveAddressUpdated(newRegenCollectiveAddress);
        regenCollectiveAddress = newRegenCollectiveAddress;
    }

    /// @inheritdoc ILiquidityAdmin
    function updateLendingContractAddress(address newLendingContractAddress) external onlyOwner {
        emit LiquidityXLendingContractAddressUpdated(
            lendingContractAddress,
            newLendingContractAddress
        );
        lendingContractAddress = newLendingContractAddress;
    }

    function requireEthTransferable() internal view {
        require(_ethTransferable, "eth not transferable");
    }

    function requireIsNotSanctioned(address addressToCheck) internal view {
        SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
        bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
        require(!isToSanctioned, "sanctioned address");
    }

    function requireCAssetBalance(
        address account,
        address cAsset,
        uint256 amount
    ) internal view {
        require(getCAssetBalance(account, cAsset) >= amount, "Insufficient cToken balance");
    }

    function sendValue(
        address asset,
        uint256 amount,
        address to
    ) public {
        requireLendingContract();
        _sendValue(asset, amount, to);
    }

    function _sendValue(
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

    // This is needed to receive ETH when calling withdrawing ETH from compund
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {
        requireEthTransferable();
    }

    function requireMaxCAssetBalance(address cAsset) internal view {
        uint256 maxCAssetBalance = maxBalanceByCAsset[cAsset];
        if (maxCAssetBalance != 0) {
            require(maxCAssetBalance >= ICERC20(cAsset).balanceOf(address(this)), "max casset");
        }
    }

    /// @inheritdoc ILiquidity
    function mintCErc20(
        address from,
        address to,
        address asset,
        uint256 amount) public returns (uint256) {
        requireLendingContract();
        return _mintCErc20(from, to, asset, amount);
    }

    function _mintCErc20(
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

    /// @inheritdoc ILiquidity
    function mintCEth(uint256 amount) public returns (uint256) {
        requireLendingContract();
        return _mintCEth(amount);
    }

    function _mintCEth(uint256 amount) internal returns (uint256) {
        address cAsset = assetToCAsset[ETH_ADDRESS];
        ICEther cToken = ICEther(cAsset);
        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        cToken.mint{ value: amount }();
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceAfter - cTokenBalanceBefore;
    }

    function requireLendingContract() internal view {
        require(msg.sender == lendingContractAddress, "not authorized");
    }

    /// @inheritdoc ILiquidity
    function burnCErc20(address asset, uint256 amount) public returns (uint256) {
        requireLendingContract();
        return _burnCErc20(asset, amount);
    }

    // @notice param amount is demoninated in the underlying asset, not cAsset
    function _burnCErc20(address asset, uint256 amount) internal returns (uint256) {
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
    function addToCAssetBalance(address account, address cAsset, uint256 amount) public {
        requireLendingContract();
        _balanceByAccountByAsset[account][cAsset].cAssetBalance += amount;  
    }

    /// @inheritdoc ILiquidity
    function subFromCAssetBalance(address account, address cAsset, uint256 amount) public {
        requireLendingContract();
        _balanceByAccountByAsset[account][cAsset].cAssetBalance -= amount;  
    }

    /// @inheritdoc ILiquidity
    function assetAmountToCAssetAmount(address asset, uint256 amount) public returns (uint256) {
        address cAsset = assetToCAsset[asset];
        ICERC20 cToken = ICERC20(cAsset);

        uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();
        return Math.divScalarByExpTruncate(amount, exchangeRateMantissa);
    }

    /// @inheritdoc ILiquidity
    function cAssetAmountToAssetAmount(address cAsset, uint256 amount) public returns (uint256) {
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
    ) public {
        requireLendingContract();
        _withdrawCBalance(account, cAsset, cTokenAmount);
    }

    function _withdrawCBalance(
        address account,
        address cAsset,
        uint256 cTokenAmount
    ) internal {
        requireCAssetBalance(account, cAsset, cTokenAmount);
        _balanceByAccountByAsset[account][cAsset].cAssetBalance -= cTokenAmount;
    }

    function renounceOwnership() public override onlyOwner {}
}