//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCastUpgradeable.sol";
import "./interfaces/compound/ICEther.sol";
import "./interfaces/niftyapes/INiftyApes.sol";
import "./interfaces/compound/ICERC20.sol";
import "./Math.sol";
import "./test/common/Console.sol";

contract NiftyApes is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    INiftyApes
{
    using ECDSAUpgradeable for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    /// @dev Internal address used for for ETH in our mappings
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @notice The maximum value that any fee on the protocol can be set to.
    ///         Fees on the protocol are denomimated in parts of 10_000.
    uint16 private constant MAX_FEE = 1_000;

    /// @notice The base value for fees in the protocol.
    uint16 private constant MAX_BPS = 10_000;

    /// @inheritdoc ILiquidity
    mapping(address => address) public override assetToCAsset;

    /// @notice The reverse mapping for assetToCAsset
    mapping(address => address) internal _cAssetToAsset;

    /// @notice The account balance for each asset of a user
    mapping(address => mapping(address => Balance)) internal _balanceByAccountByAsset;

    /// @inheritdoc ILiquidity
    mapping(address => uint256) public override maxBalanceByCAsset;

    /// @dev A mapping for a NFT to a loan auction.
    ///      The mapping has to be broken into two parts since an NFT is denomiated by its address (first part)
    ///      and its nftId (second part) in our code base.
    mapping(address => mapping(uint256 => LoanAuction)) private _loanAuctions;

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

    /// @inheritdoc ILending
    uint16 public loanDrawFeeProtocolBps;

    /// @inheritdoc ILending
    uint16 public refinancePremiumLenderBps;

    /// @inheritdoc ILending
    uint16 public refinancePremiumProtocolBps;

    /// @notice The initializer for the NiftyApes protocol.
    ///         Nifty Apes is intended to be deployed behind a proxy amd thus needs to initialize
    ///         its state outsize of a constructor.
    function initialize() public initializer {
        EIP712Upgradeable.__EIP712_init("NiftyApes", "0.0.1");

        loanDrawFeeProtocolBps = 50;
        refinancePremiumLenderBps = 50;
        refinancePremiumProtocolBps = 50;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    }

    /// @inheritdoc INiftyApesAdmin
    function setCAssetAddress(address asset, address cAsset) external onlyOwner {
        require(assetToCAsset[asset] == address(0), "asset already set");
        require(_cAssetToAsset[cAsset] == address(0), "casset already set");
        assetToCAsset[asset] = cAsset;
        _cAssetToAsset[cAsset] = asset;

        emit NewAssetWhitelisted(asset, cAsset);
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
    function supplyErc20(address asset, uint256 numTokensToSupply)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cAsset = getCAsset(asset);

        uint256 cTokensMinted = mintCErc20(msg.sender, address(this), asset, numTokensToSupply);

        _balanceByAccountByAsset[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        requireMaxCAssetBalance(cAsset);

        emit Erc20Supplied(msg.sender, asset, numTokensToSupply, cTokensMinted);

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

        cToken.safeTransferFrom(msg.sender, address(this), cTokenAmount);

        _balanceByAccountByAsset[msg.sender][cAsset].cAssetBalance += cTokenAmount;

        requireMaxCAssetBalance(cAsset);

        emit CErc20Supplied(msg.sender, cAsset, cTokenAmount);
    }

    /// @inheritdoc ILiquidity
    function withdrawErc20(address asset, uint256 amountToWithdraw)
        public
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cAsset = getCAsset(asset);
        IERC20Upgradeable underlying = IERC20Upgradeable(asset);

        uint256 cTokensBurnt = burnCErc20(asset, amountToWithdraw);

        withdrawCBalance(msg.sender, cAsset, cTokensBurnt);

        underlying.safeTransfer(msg.sender, amountToWithdraw);

        emit Erc20Withdrawn(msg.sender, asset, amountToWithdraw, cTokensBurnt);

        return cTokensBurnt;
    }

    /// @inheritdoc ILiquidity
    function withdrawCErc20(address cAsset, uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
    {
        // Making sure a mapping for cAsset exists
        getAsset(cAsset);
        IERC20Upgradeable cToken = IERC20Upgradeable(cAsset);

        withdrawCBalance(msg.sender, cAsset, amountToWithdraw);

        cToken.safeTransfer(msg.sender, amountToWithdraw);

        emit CErc20Withdrawn(msg.sender, cAsset, amountToWithdraw);
    }

    /// @inheritdoc ILiquidity
    function supplyEth() external payable whenNotPaused nonReentrant returns (uint256) {
        address cAsset = getCAsset(ETH_ADDRESS);

        uint256 cTokensMinted = mintCEth(msg.value);

        _balanceByAccountByAsset[msg.sender][cAsset].cAssetBalance += cTokensMinted;

        requireMaxCAssetBalance(cAsset);

        emit EthSupplied(msg.sender, msg.value, cTokensMinted);

        return cTokensMinted;
    }

    /// @inheritdoc ILiquidity
    function withdrawEth(uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address cAsset = getCAsset(ETH_ADDRESS);
        uint256 cTokensBurnt = burnCErc20(ETH_ADDRESS, amountToWithdraw);

        withdrawCBalance(msg.sender, cAsset, cTokensBurnt);

        payable(msg.sender).sendValue(amountToWithdraw);

        emit EthWithdrawn(msg.sender, amountToWithdraw, cTokensBurnt);

        return cTokensBurnt;
    }

    /// @inheritdoc ILending
    function getLoanAuction(address nftContractAddress, uint256 nftId)
        external
        view
        returns (LoanAuction memory)
    {
        return _loanAuctions[nftContractAddress][nftId];
    }

    /// @inheritdoc ILending
    function getOfferHash(Offer memory offer) public view returns (bytes32 signedOffer) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        offer.creator,
                        offer.nftContractAddress,
                        offer.nftId,
                        offer.asset,
                        offer.amount,
                        offer.interestRateBps,
                        offer.duration,
                        offer.expiration,
                        offer.fixedTerms,
                        offer.floorTerm
                    )
                )
            );
    }

    /// @inheritdoc ILending
    function getOfferSignatureStatus(bytes calldata signature) external view returns (bool) {
        return _cancelledOrFinalized[signature];
    }

    /// @inheritdoc ILending
    function getOfferSigner(
        bytes32 offerHash, // hash of offer
        bytes memory signature //proof the actor signed the offer
    ) public pure override returns (address) {
        return ECDSAUpgradeable.recover(offerHash, signature);
    }

    /// @inheritdoc ILending
    function withdrawOfferSignature(Offer memory offer, bytes calldata signature)
        external
        whenNotPaused
    {
        requireAvailableSignature(signature);

        bytes32 offerHash = getOfferHash(offer);
        address signer = getOfferSigner(offerHash, signature);

        requireSigner(signer, msg.sender);

        markSignatureUsed(signature);

        emit SigOfferCancelled(offer.nftContractAddress, offer.nftId, signature);
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

    /// @inheritdoc ILending
    function getOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external view returns (Offer memory) {
        return getOfferBook(nftContractAddress, nftId, floorTerm)[offerHash];
    }

    /// @inheritdoc ILending
    function createOffer(Offer calldata offer) external whenNotPaused {
        address cAsset = getCAsset(offer.asset);

        requireOfferCreator(offer.creator, msg.sender);

        uint256 offerTokens = assetAmountToCAssetAmount(offer.asset, offer.amount);

        requireCAssetBalance(msg.sender, cAsset, offerTokens);

        mapping(bytes32 => Offer) storage offerBook = getOfferBook(
            offer.nftContractAddress,
            offer.nftId,
            offer.floorTerm
        );

        bytes32 offerHash = getOfferHash(offer);

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

    /// @inheritdoc ILending
    function removeOffer(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external whenNotPaused {
        // Get pointer to offer book
        mapping(bytes32 => Offer) storage offerBook = getOfferBook(
            nftContractAddress,
            nftId,
            floorTerm
        );

        // Create a copy here so that we can log out the event below
        Offer memory offer = offerBook[offerHash];

        requireOfferCreator(offer.creator, msg.sender);

        delete offerBook[offerHash];

        emit OfferRemoved(offer.creator, offer.asset, offer.nftContractAddress, offer, offerHash);
    }

    /// @inheritdoc ILending
    function executeLoanByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bytes32 offerHash,
        bool floorTerm
    ) external payable whenNotPaused nonReentrant {
        mapping(bytes32 => Offer) storage offerBook = getOfferBook(
            nftContractAddress,
            nftId,
            floorTerm
        );
        Offer memory offer = offerBook[offerHash];

        _executeLoanInternal(offer, offer.creator, msg.sender, nftId);
    }

    /// @inheritdoc ILending
    function executeLoanByBorrowerSignature(
        Offer calldata offer,
        bytes calldata signature,
        // TODO(dankurka): Add a good explanation
        uint256 nftId
    ) external payable whenNotPaused nonReentrant {
        requireAvailableSignature(signature);

        address lender = getOfferSigner(getOfferHash(offer), signature);
        requireOfferCreator(offer, lender);

        if (!offer.floorTerm) {
            requireMatchingNftId(offer, nftId);
        }

        markSignatureUsed(signature);

        // execute state changes for executeLoanByBid
        _executeLoanInternal(offer, lender, msg.sender, nftId);

        emit SigOfferFinalized(offer.nftContractAddress, nftId, signature);
    }

    /// @inheritdoc ILending
    function executeLoanByLender(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm,
        bytes32 offerHash
    ) public payable whenNotPaused nonReentrant {
        Offer memory offer = floorTerm
            ? _floorOfferBooks[nftContractAddress][offerHash]
            : _nftOfferBooks[nftContractAddress][nftId][offerHash];

        // execute state changes for executeLoanByAsk
        _executeLoanInternal(offer, msg.sender, offer.creator, nftId);
    }

    /// @inheritdoc ILending
    function executeLoanByLenderSignature(Offer calldata offer, bytes calldata signature)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        requireAvailableSignature(signature);

        address borrower = getOfferSigner(getOfferHash(offer), signature);
        requireOfferCreator(offer, borrower);

        markSignatureUsed(signature);

        _executeLoanInternal(offer, msg.sender, borrower, offer.nftId);

        emit SigOfferFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    /**
     * @notice Handles checks, state transitions, and value/asset transfers for executeLoanbyLender
     * @param offer The details of a loan auction offer
     * @param lender The prospective lender
     * @param borrower The prospective borrower and owner of the NFT
     */
    function _executeLoanInternal(
        Offer memory offer,
        address lender,
        address borrower,
        uint256 nftId
    ) internal {
        requireOfferPresent(offer);

        address cAsset = getCAsset(offer.asset);

        LoanAuction storage loanAuction = _loanAuctions[offer.nftContractAddress][offer.nftId];

        requireNoOpenLoan(loanAuction);
        requireOfferNotExpired(offer);
        requireMinDurationForOffer(offer);
        requireNftOwner(offer.nftContractAddress, nftId, borrower);

        createLoan(loanAuction, offer, lender, borrower);

        transferNft(offer.nftContractAddress, offer.nftId, borrower, address(this));

        uint256 cTokensBurned = burnCErc20(offer.asset, offer.amount);
        withdrawCBalance(lender, cAsset, cTokensBurned);

        sendValue(offer.asset, offer.amount, borrower);

        emit LoanExecuted(lender, borrower, offer.nftContractAddress, offer.nftId, offer);
    }

    /// @inheritdoc ILending
    function refinanceByBorrower(
        address nftContractAddress,
        uint256 nftId,
        bool floorTerm,
        bytes32 offerHash
    ) external payable whenNotPaused nonReentrant {
        Offer memory offer = floorTerm
            ? _floorOfferBooks[nftContractAddress][offerHash]
            : _nftOfferBooks[nftContractAddress][nftId][offerHash];

        if (!offer.floorTerm) {
            requireMatchingNftId(offer, nftId);
        }

        requireNftOwner(_loanAuctions[nftContractAddress][nftId], msg.sender);
        _refinanceByBorrower(offer, offer.creator, nftId);
    }

    /// @inheritdoc ILending
    function refinanceByBorrowerSignature(
        Offer calldata offer,
        bytes calldata signature,
        uint256 nftId
    ) external payable whenNotPaused nonReentrant {
        address prospectiveLender = getOfferSigner(getOfferHash(offer), signature);

        requireOfferCreator(offer, prospectiveLender);

        if (!offer.floorTerm) {
            requireMatchingNftId(offer, nftId);
        }

        requireNftOwner(_loanAuctions[offer.nftContractAddress][offer.nftId], msg.sender);

        markSignatureUsed(signature);

        _refinanceByBorrower(offer, offer.creator, nftId);

        emit SigOfferFinalized(offer.nftContractAddress, offer.nftId, signature);
    }

    /// @inheritdoc ILending
    function refinanceByLender(Offer calldata offer) external payable whenNotPaused nonReentrant {
        LoanAuction storage loanAuction = _loanAuctions[offer.nftContractAddress][offer.nftId];

        requireOpenLoan(loanAuction);

        requireLoanNotExpired(loanAuction);

        requireOfferParity(loanAuction, offer);

        requireValidDurationUpdate(loanAuction, offer);

        _refinanceByLender(offer, offer.creator, offer.nftId);
    }

    function _refinanceByBorrower(
        Offer memory offer,
        address prospectiveLender,
        uint256 nftId // TODO(dankurka): Bug
    ) internal {
        (LoanAuction storage loanAuction, address cAsset) = _refinanceCheckState(offer);

        updateInterest(loanAuction);

        uint256 fullAmount = loanAuction.amountDrawn + loanAuction.historicLenderInterest;

        require(
            offer.amount >= fullAmount,
            "The loan offer must exceed the present outstanding balance."
        );

        // Get the full amount of the loan outstanding balance in cTokens
        uint256 fullCTokenAmount = assetAmountToCAssetAmount(offer.asset, fullAmount);

        withdrawCBalance(prospectiveLender, cAsset, fullCTokenAmount);
        _balanceByAccountByAsset[loanAuction.lender][cAsset].cAssetBalance += fullCTokenAmount;

        // update Loan state
        loanAuction.lender = prospectiveLender;
        loanAuction.amount = offer.amount;
        loanAuction.interestRateBps = offer.interestRateBps;
        loanAuction.duration = offer.duration;
        loanAuction.amountDrawn = SafeCastUpgradeable.toUint128(fullAmount);

        emit Refinance(prospectiveLender, offer.nftContractAddress, offer.nftId, offer);
    }

    function _refinanceByLender(
        Offer memory offer,
        address prospectiveLender,
        uint256 nftId // TODO(dankurka): Bug
    ) internal {
        (LoanAuction storage loanAuction, address cAsset) = _refinanceCheckState(offer);

        uint32 originalInterestStart = loanAuction.timeOfInterestStart;

        updateInterest(loanAuction);

        // update LoanAuction struct
        loanAuction.amount = offer.amount;
        loanAuction.interestRateBps = offer.interestRateBps;
        loanAuction.duration = offer.duration;

        if (loanAuction.lender == prospectiveLender) {
            // If current lender is refinancing the loan they do not need to pay any fees or buy themselves out.
            // require prospective lender has sufficient available balance to refinance loan

            uint256 cTokenAmountDrawn = assetAmountToCAssetAmount(
                offer.asset,
                loanAuction.amountDrawn
            );

            uint256 cTokenOfferAmount = assetAmountToCAssetAmount(offer.asset, offer.amount);

            uint256 additionalTokens = cTokenOfferAmount - cTokenAmountDrawn;

            require(
                getCAssetBalance(prospectiveLender, cAsset) >= additionalTokens,
                "lender balance"
            );
        } else {
            // calculate interest earned
            uint256 interestAndPremiumOwedToCurrentLender = loanAuction.historicLenderInterest +
                ((loanAuction.amountDrawn * refinancePremiumLenderBps) / MAX_BPS);

            uint256 protocolPremium = (loanAuction.amountDrawn * refinancePremiumProtocolBps) /
                MAX_BPS;
            // calculate fullRefinanceAmount
            uint256 fullAmount = interestAndPremiumOwedToCurrentLender +
                protocolPremium +
                loanAuction.amountDrawn;

            // If refinancing is done by another lender they must buy out the loan and pay fees
            uint256 fullCTokenAmount = assetAmountToCAssetAmount(offer.asset, fullAmount);

            // require prospective lender has sufficient available balance to refinance loan
            require(
                getCAssetBalance(prospectiveLender, cAsset) >= fullCTokenAmount,
                "lender balance"
            );

            uint256 protocolPremimuimInCtokens = assetAmountToCAssetAmount(
                offer.asset,
                protocolPremium
            );

            address currentlender = loanAuction.lender;

            // update LoanAuction lender
            loanAuction.lender = prospectiveLender;

            _balanceByAccountByAsset[currentlender][cAsset].cAssetBalance +=
                fullCTokenAmount -
                protocolPremimuimInCtokens;
            _balanceByAccountByAsset[prospectiveLender][cAsset].cAssetBalance -= fullCTokenAmount;
            _balanceByAccountByAsset[owner()][cAsset].cAssetBalance += protocolPremimuimInCtokens;
        }

        emit Refinance(prospectiveLender, offer.nftContractAddress, offer.nftId, offer);
    }

    function _refinanceCheckState(Offer memory offer)
        internal
        returns (LoanAuction storage loanAuction, address)
    {
        LoanAuction storage loanAuction = _loanAuctions[offer.nftContractAddress][offer.nftId];

        requireNoFixedTerm(loanAuction);
        requireOpenLoan(loanAuction);
        requireOfferNotExpired(offer);

        requireMatchingAsset(offer.asset, loanAuction.asset);

        return (loanAuction, getCAsset(offer.asset));
    }

    /// @inheritdoc ILending
    function drawLoanAmount(
        address nftContractAddress,
        uint256 nftId,
        uint256 drawAmount
    ) external whenNotPaused nonReentrant {
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];

        address cAsset = getCAsset(loanAuction.asset);

        requireOpenLoan(loanAuction);
        requireNftOwner(loanAuction, msg.sender);
        requireFundsAvailable(loanAuction, drawAmount);
        requireLoanNotExpired(loanAuction);

        updateInterest(loanAuction);
        loanAuction.amountDrawn += SafeCastUpgradeable.toUint128(drawAmount);

        uint256 cTokensBurnt = burnCErc20(loanAuction.asset, drawAmount);
        withdrawCBalance(loanAuction.lender, cAsset, cTokensBurnt);

        sendValue(loanAuction.asset, drawAmount, loanAuction.nftOwner);

        emit AmountDrawn(nftContractAddress, nftId, drawAmount, loanAuction.amountDrawn);
    }

    /// @inheritdoc ILending
    function repayLoan(address nftContractAddress, uint256 nftId)
        external
        payable
        override
        whenNotPaused
    {
        RepayLoanStruct memory rls = RepayLoanStruct({
            nftContractAddress: nftContractAddress,
            nftId: nftId,
            repayFull: true,
            paymentAmount: 0,
            checkMsgSender: true
        });
        _repayLoanAmount(rls);
    }

    /// @inheritdoc ILending
    function repayLoanForAccount(address nftContractAddress, uint256 nftId)
        external
        payable
        override
        whenNotPaused
    {
        RepayLoanStruct memory rls = RepayLoanStruct({
            nftContractAddress: nftContractAddress,
            nftId: nftId,
            repayFull: true,
            paymentAmount: 0,
            checkMsgSender: false
        });

        _repayLoanAmount(rls);
    }

    /// @inheritdoc ILending
    function partialRepayLoan(
        address nftContractAddress,
        uint256 nftId,
        uint256 amount
    ) external payable whenNotPaused nonReentrant {
        RepayLoanStruct memory rls = RepayLoanStruct({
            nftContractAddress: nftContractAddress,
            nftId: nftId,
            repayFull: false,
            paymentAmount: amount,
            checkMsgSender: true
        });

        _repayLoanAmount(rls);
    }

    /// @dev Struct exitst since we ran out of stack space in _repayLoan
    struct RepayLoanStruct {
        address nftContractAddress;
        uint256 nftId;
        bool repayFull;
        uint256 paymentAmount;
        bool checkMsgSender;
    }

    function _repayLoanAmount(RepayLoanStruct memory rls) internal {
        LoanAuction storage loanAuction = _loanAuctions[rls.nftContractAddress][rls.nftId];
        address cAsset = getCAsset(loanAuction.asset);

        if (!rls.repayFull) {
            if (loanAuction.asset == ETH_ADDRESS) {
                requireMsgValue(rls.paymentAmount);
            }
            require(rls.paymentAmount < loanAuction.amountDrawn, "use repayLoan");
        }

        requireOpenLoan(loanAuction);

        if (rls.checkMsgSender) {
            require(msg.sender == loanAuction.nftOwner, "msg.sender is not the borrower");
        }

        updateInterest(loanAuction);

        uint256 payment = rls.repayFull
            ? loanAuction.historicLenderInterest +
                loanAuction.historicProtocolInterest +
                loanAuction.amountDrawn
            : rls.paymentAmount;

        uint256 cTokensMinted = handleLoanPayment(rls, loanAuction, payment);

        payoutCTokenBalances(loanAuction, cAsset, cTokensMinted, payment);

        if (rls.repayFull) {
            transferNft(rls.nftContractAddress, rls.nftId, address(this), loanAuction.nftOwner);

            emit LoanRepaid(
                rls.nftContractAddress,
                rls.nftId,
                loanAuction.nftOwner,
                loanAuction.asset,
                payment
            );

            delete _loanAuctions[rls.nftContractAddress][rls.nftId];
        } else {
            loanAuction.amountDrawn -= SafeCastUpgradeable.toUint128(payment);

            emit PartialRepayment(
                rls.nftContractAddress,
                rls.nftId,
                loanAuction.asset,
                rls.paymentAmount
            );
        }
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

    /// @inheritdoc ILending
    function seizeAsset(address nftContractAddress, uint256 nftId)
        external
        whenNotPaused
        nonReentrant
    {
        LoanAuction storage loanAuction = _loanAuctions[nftContractAddress][nftId];
        getCAsset(loanAuction.asset); // Ensure asset mapping exists
        requireOpenLoan(loanAuction);

        requireLoanExpired(loanAuction);

        address currentLender = loanAuction.lender;
        address currentBorrower = loanAuction.nftOwner;

        delete _loanAuctions[nftContractAddress][nftId];

        transferNft(nftContractAddress, nftId, address(this), currentLender);

        emit AssetSeized(currentLender, currentBorrower, nftContractAddress, nftId);
    }

    /// @inheritdoc ILending
    function ownerOf(address nftContractAddress, uint256 nftId) public view returns (address) {
        return _loanAuctions[nftContractAddress][nftId].nftOwner;
    }

    function updateInterest(LoanAuction storage loanAuction) internal {
        (uint256 lenderInterest, uint256 protocolInterest) = calculateInterestAccrued(loanAuction);

        loanAuction.historicLenderInterest += SafeCastUpgradeable.toUint128(lenderInterest);
        loanAuction.historicProtocolInterest += SafeCastUpgradeable.toUint128(protocolInterest);
        loanAuction.timeOfInterestStart = SafeCastUpgradeable.toUint32(block.timestamp);
    }

    /// @inheritdoc ILending
    function calculateInterestAccrued(address nftContractAddress, uint256 nftId)
        public
        view
        returns (uint256, uint256)
    {
        return calculateInterestAccrued(_loanAuctions[nftContractAddress][nftId]);
    }

    function calculateInterestAccrued(LoanAuction storage loanAuction)
        internal
        view
        returns (uint256 lenderInterest, uint256 protocolInterest)
    {
        uint256 timeOfInterestStart = loanAuction.timeOfInterestStart;

        if (block.timestamp <= timeOfInterestStart) {
            protocolInterest = 0;
            lenderInterest = 0;
        } else {
            // Time since we last updated the loan
            uint256 timeOutstanding = block.timestamp - timeOfInterestStart;

            uint256 interestBase = (loanAuction.amountDrawn * timeOutstanding) /
                loanAuction.duration;

            lenderInterest = (loanAuction.interestRateBps * interestBase) / MAX_BPS;

            protocolInterest = (loanDrawFeeProtocolBps * interestBase) / MAX_BPS;
        }
    }

    /// @inheritdoc INiftyApesAdmin
    function updateLoanDrawProtocolFee(uint16 newLoanDrawProtocolFeeBps) external onlyOwner {
        require(newLoanDrawProtocolFeeBps <= MAX_FEE, "max fee");
        loanDrawFeeProtocolBps = newLoanDrawProtocolFeeBps;
    }

    /// @inheritdoc INiftyApesAdmin
    function updateRefinancePremiumLenderFee(uint16 newPremiumLenderBps) external onlyOwner {
        require(newPremiumLenderBps <= MAX_FEE, "max fee");
        refinancePremiumLenderBps = newPremiumLenderBps;
    }

    /// @inheritdoc INiftyApesAdmin
    function updateRefinancePremiumProtocolFee(uint16 newPremiumProtocolBps) external onlyOwner {
        require(newPremiumProtocolBps <= MAX_FEE, "max fee");
        refinancePremiumProtocolBps = newPremiumProtocolBps;
    }

    function markSignatureUsed(bytes memory signature) internal {
        _cancelledOrFinalized[signature] = true;
    }

    function requireOfferPresent(Offer memory offer) internal pure {
        require(offer.asset != address(0), "no offer");
    }

    function requireNoOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.timeOfInterestStart == 0, "Loan already open");
    }

    function requireOpenLoan(LoanAuction storage loanAuction) internal view {
        require(loanAuction.timeOfInterestStart != 0, "loan not active");
    }

    function requireLoanExpired(LoanAuction storage loanAuction) internal view {
        require(
            block.timestamp >= loanAuction.timeOfInterestStart + loanAuction.duration,
            "loan not expired"
        );
    }

    function requireLoanNotExpired(LoanAuction storage loanAuction) internal view {
        require(
            block.timestamp < loanAuction.timeOfInterestStart + loanAuction.duration,
            "loan expired"
        );
    }

    function requireOfferNotExpired(Offer memory offer) internal view {
        require(offer.expiration > block.timestamp, "offer expired");
    }

    function requireMinDurationForOffer(Offer memory offer) internal view {
        require(offer.duration >= 1 days, "offer duration");
    }

    function requireNoFixedTerm(LoanAuction storage loanAuction) internal view {
        require(!loanAuction.fixedTerms, "fixed term loan");
    }

    function requireNftOwner(
        address nftContractAddress,
        uint256 nftId,
        address owner
    ) internal view {
        require(IERC721Upgradeable(nftContractAddress).ownerOf(nftId) == owner, "nft owner");
    }

    function requireMatchingAsset(address asset1, address asset2) internal pure {
        require(asset1 == asset2, "asset mismatch");
    }

    function requireAvailableSignature(bytes memory signature) internal {
        require(!_cancelledOrFinalized[signature], "signature not available");
    }

    function requireFundsAvailable(LoanAuction storage loanAuction, uint256 drawAmount) internal {
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
        uint256 interestRateBps = loanAuction.interestRateBps;
        uint256 duration = loanAuction.duration;

        // Better amount
        if (
            offer.amount > amount &&
            offer.interestRateBps <= interestRateBps &&
            offer.duration >= duration
        ) {
            return;
        }

        // Lower interest rate
        if (
            offer.amount >= amount &&
            offer.interestRateBps < interestRateBps &&
            offer.duration >= duration
        ) {
            return;
        }

        // Longer duration
        if (
            offer.amount >= amount &&
            offer.interestRateBps <= interestRateBps &&
            offer.duration > duration
        ) {
            return;
        }

        revert("not an improvement");
    }

    function requireValidDurationUpdate(LoanAuction storage loanAuction, Offer memory offer)
        internal
        view
    {
        // If the only part that is updated is the duration we enfore that its been changed by
        // at least one day
        // This prevents lenders from refinancing loands with too small of change
        if (
            offer.amount == loanAuction.amount &&
            offer.interestRateBps == loanAuction.interestRateBps &&
            offer.duration > loanAuction.duration
        ) {
            require(offer.duration >= (loanAuction.duration + 1 days), "24 hours min");
        }
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
        loanAuction.interestRateBps = offer.interestRateBps;
        loanAuction.duration = offer.duration;
        loanAuction.timeOfInterestStart = SafeCastUpgradeable.toUint32(block.timestamp);
        loanAuction.amountDrawn = offer.amount;
        loanAuction.fixedTerms = offer.fixedTerms;
    }

    function transferNft(
        address nftContractAddress,
        uint256 nftId,
        address from,
        address to
    ) internal {
        IERC721Upgradeable(nftContractAddress).transferFrom(from, to, nftId);
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
            (loanAuction.amountDrawn + loanAuction.historicLenderInterest)) / totalPayment;
        uint256 cTokensToProtocol = (totalCTokens * loanAuction.historicProtocolInterest) /
            totalPayment;

        _balanceByAccountByAsset[loanAuction.lender][cAsset].cAssetBalance += cTokensToLender;
        _balanceByAccountByAsset[owner()][cAsset].cAssetBalance += cTokensToProtocol;
    }

    // This is needed to receive ETH when calling withdrawing ETH from compund
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function requireMaxCAssetBalance(address cAsset) internal {
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

    function burnCErc20(address asset, uint256 amount) internal returns (uint256) {
        address cAsset = assetToCAsset[asset];
        ICERC20 cToken = ICERC20(cAsset);

        uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
        require(cToken.redeemUnderlying(amount) == 0, "redeemUnderlying failed");
        uint256 cTokenBalanceAfter = cToken.balanceOf(address(this));
        return cTokenBalanceBefore - cTokenBalanceAfter;
    }

    function assetAmountToCAssetAmount(address asset, uint256 amount) internal returns (uint256) {
        address cAsset = assetToCAsset[asset];
        ICERC20 cToken = ICERC20(cAsset);

        uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();
        return Math.divScalarByExpTruncate(amount, exchangeRateMantissa);
    }

    function getCAsset(address asset) internal view returns (address) {
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
}
