// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// A handler contract allows you to control which functions Foundry will call during
// invariant testing, ensuirng realistic scenarios .

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // the max uint96 value
    uint256 public timeMintIsCalled;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    // deposit collateral
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {

        ERC20Mock collateralToken = _getCollateralTokenFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        // lets prank user and approve dscEngine to use the tokens on behalf of user
        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amountCollateral);
        collateralToken.approve(address(dscEngine), amountCollateral);
        // and then deposit
        dscEngine.depositCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
    }

    // mint dsc
    function mintDsc(uint256 amount) public {
        
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine.getUserInformation(msg.sender);

        int256 maxDscToMint =  ((int256(totalCollateralValueInUsd) / 2 ) - int256(totalDscMinted));
        if (maxDscToMint <= 0) {
            return;
        } 
        
        // Make sure maxDscToMint is at least 1 to avoid "Max is less than min" error
        if (uint256(maxDscToMint) < 1) {
            return;
        }
        
        amount = bound(amount, 1, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        
        vm.startPrank(msg.sender);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        timeMintIsCalled++;
    }

    // redeem collateral
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralTokenFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralAmount(msg.sender, address(collateralToken));

        if (maxCollateralToRedeem == 0) {
            return;
        }
        
        // Check if the user has any DSC minted
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getUserInformation(msg.sender);
        
        // If user has DSC, we need to be careful about how much collateral to redeem
        if (totalDscMinted > 0) {
            // Calculate the minimum collateral needed for health factor (with 2x safety margin)
            uint256 minCollateralValueNeeded = totalDscMinted * 2; // 150% collateralization with safety margin
            
            // If we can't redeem any safely, just return
            if (collateralValueInUsd <= minCollateralValueNeeded) {
                return;
            }
            
            // Calculate max collateral we can redeem while maintaining health factor
            uint256 maxCollateralValueToRedeem = collateralValueInUsd - minCollateralValueNeeded;
            
            // Use getTokenAmountFromUsd for precision
            uint256 maxTokensToRedeem = dscEngine.getTokenAmountFromUsd(address(collateralToken), maxCollateralValueToRedeem);
            
            // Ensure we don't try to redeem more than available
            if (maxTokensToRedeem == 0) {
                return;
            }
            
            // Cap at the actual amount of collateral the user has
            maxTokensToRedeem = maxTokensToRedeem > maxCollateralToRedeem ? maxCollateralToRedeem : maxTokensToRedeem;
            
            amountCollateral = bound(amountCollateral, 1, maxTokensToRedeem);
        } else {
            // If no DSC minted, we can redeem any amount up to max
            amountCollateral = bound(amountCollateral, 1, maxCollateralToRedeem);
        }
        
        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
    }

    // helper function
    function _getCollateralTokenFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
