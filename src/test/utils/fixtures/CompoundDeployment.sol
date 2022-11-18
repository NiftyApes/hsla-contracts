// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../compound-contracts/CTokenInterfaces.sol";
import "../../../compound-contracts/CErc20Delegate.sol";
import "../../../compound-contracts/CErc20Delegator.sol";
import "../../../compound-contracts/Comptroller.sol";
import "../../../compound-contracts/Unitroller.sol";
import "../../../compound-contracts/JumpRateModelV2.sol";
import "../../../compound-contracts/Governance/Comp.sol";

import "../../mock/CERC20Mock.sol";

import "./NiftyApesDeployment.sol";

import "forge-std/Test.sol";

// deploy & initializes bCompound Contracts
contract CompoundDeployment is Test, NiftyApesDeployment {
    CErc20Delegate cTokenImplementation;
    CErc20Delegator cErc20;
    CToken cToken;
    Comptroller comptroller;
    Unitroller unitroller;
    JumpRateModelV2 interestRateModel;
    Comp bComp;

    bool internal BCOMP = false;

    function setUp() public virtual override {
        super.setUp();

        try vm.envBool("BCOMP") returns (bool isBComp) {
            BCOMP = isBComp;
        } catch (bytes memory) {
            // This catches revert that occurs if env variable not supplied
        }

        vm.startPrank(owner);

        bComp = new Comp(owner);
        comptroller = new Comptroller(address(bComp));
        unitroller = new Unitroller();
        interestRateModel = new JumpRateModelV2(1, 1, 1, 100, owner);

        unitroller._setPendingImplementation(address(comptroller));

        comptroller._become(unitroller);
        ComptrollerInterface(address(unitroller))._setSeizePaused(true);
        ComptrollerInterface(address(unitroller))._setBCompAddress(address(bComp));

        // deploy and initialize implementation contracts
        cTokenImplementation = new CErc20Delegate();

        // deploy cTokenDelegator
        cErc20 = new CErc20Delegator(
            address(daiToken),
            ComptrollerInterface(address(unitroller)),
            interestRateModel,
            2**18,
            "niftyApesWrappedXDai",
            "bwxDai",
            8,
            owner,
            address(cTokenImplementation),
            bytes("")
        );

        // declare interfaces
        cToken = CToken(address(cErc20));

        ComptrollerInterface(address(unitroller))._supportMarket(cToken);
        ComptrollerInterface(address(unitroller))._setBorrowPaused(cToken, true);

        if (BCOMP) {
            cDAIToken = CERC20Mock(address(cErc20));
            liquidity.setCAssetAddress(address(daiToken), address(cDAIToken));
            liquidity.setMaxCAssetBalance(address(cDAIToken), ~uint256(0));
        }

        vm.stopPrank();

        vm.label(address(0), "NULL !!!!! ");
    }
}