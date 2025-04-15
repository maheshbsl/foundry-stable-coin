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

    // redeem collateral
    function redeemCollateral(uint256 collteralSeed, uint256 amountCollateral) public {

        ERC20Mock collateralToken = _getCollateralTokenFromSeed(collteralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralAmount(msg.sender, address(collateralToken));

        if (maxCollateralToRedeem == 0) {
            return;
        }
        console.log(msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        console.log("amount collateral TO redeem: ", amountCollateral);
        console.log("total collateral user has: ", maxCollateralToRedeem);
        
        dscEngine.redeemCollateral(address(collateralToken), amountCollateral);
    }

    // helper function
    function _getCollateralTokenFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
