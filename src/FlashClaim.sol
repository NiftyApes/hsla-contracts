//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "./interfaces/niftyapes/lending/ILending.sol";
import "./interfaces/sanctions/SanctionsList.sol";
import "./interfaces/niftyapes/flashClaim/IFlashClaim.sol";
import "./flashClaim/interfaces/IFlashClaimReceiver.sol";

/// @notice Extension of NiftApes lending contract to allow for flash claims of NFTs
contract NiftyApesFlashClaim is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    IFlashClaim
{
    using AddressUpgradeable for address payable;

    /// @dev Internal constant address for the Chainalysis OFAC sanctions oracle
    address private constant SANCTIONS_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    /// @inheritdoc IFlashClaim
    address public lendingContractAddress;

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

    /// @inheritdoc IFlashClaimAdmin
    function updateLendingContractAddress(address newLendingContractAddress) external onlyOwner {
        require(address(newLendingContractAddress) != address(0), "00035");
        emit FlashClaimXLendingContractAddressUpdated(
            lendingContractAddress,
            newLendingContractAddress
        );
        lendingContractAddress = newLendingContractAddress;
    }

    /// @inheritdoc IFlashClaimAdmin
    function pauseSanctions() external onlyOwner {
        _sanctionsPause = true;
        emit FlashClaimSanctionsPaused();
    }

    /// @inheritdoc IFlashClaimAdmin
    function unpauseSanctions() external onlyOwner {
        _sanctionsPause = false;
        emit FlashClaimSanctionsUnpaused();
    }

    /// @inheritdoc IFlashClaimAdmin
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IFlashClaimAdmin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IFlashClaim
    function flashClaim(
        address nftContractAddress,
        uint256 nftId,
        address receiverAddress
    ) external whenNotPaused nonReentrant {
        address nftOwner = _requireNftOwner(nftContractAddress, nftId);
        _requireIsNotSanctioned(msg.sender);
        _requireIsNotSanctioned(nftOwner);

        // instantiate receiver contract
        IFlashClaimReceiver receiver = IFlashClaimReceiver(receiverAddress);

        // transfer NFT
        ILending(lendingContractAddress).transferNft(
            nftContractAddress,
            nftId,
            lendingContractAddress,
            receiverAddress
        );

        // execute firewalled external arbitrary functionality
        // function must approve this contract to transferFrom NFT in order to return lending.sol
        require(receiver.executeOperation(nftContractAddress, nftId, address(this)), "00052");

        // transfer nft back to Lending.sol
        _transferNft(nftContractAddress, nftId, receiverAddress, lendingContractAddress);

        // explicitly require NFt returned to Lending.sol
        _requireNftReturned(nftContractAddress, nftId);

        // emit event
        emit FlashClaim(nftContractAddress, nftId, receiverAddress);
    }

    function _transferNft(
        address nftContractAddress,
        uint256 nftId,
        address from,
        address to
    ) internal {
        IERC721Upgradeable(nftContractAddress).safeTransferFrom(from, to, nftId);
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

    function _requireNftReturned(address nftContractAddress, uint256 nftId) internal view {
        require(
            IERC721Upgradeable(nftContractAddress).ownerOf(nftId) == lendingContractAddress,
            "00053"
        );
    }

    function _requireIsNotSanctioned(address addressToCheck) internal view {
        if (!_sanctionsPause) {
            SanctionsList sanctionsList = SanctionsList(SANCTIONS_CONTRACT);
            bool isToSanctioned = sanctionsList.isSanctioned(addressToCheck);
            require(!isToSanctioned, "00017");
        }
    }

    receive() external payable {
        _requireEthTransferable();
    }
}
