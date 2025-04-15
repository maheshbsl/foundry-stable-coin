    // SPDX-License-Identifier: MIT

// // will have our invariants aka properties

// // what are our invariants?

// // 1. The total supply of dsc should be less than the total value of collateral

pragma solidity ^0.8.27;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    Handler handler;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        // targetContract(address(dscEngine));

        handler = new Handler(dsc, dscEngine);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        //compare it to all the debt (dsc)

        // total supply of the dsc
        uint256 totalSupply = dsc.totalSupply();
        // total amount of weth deposited in the protocol
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        // total amount of wbtc deposited in the protocol
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        // get the weth value in usd
        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);

        // get the wbtc value in usd
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        // total value of all the collateral in the protocol
        uint256 totalCollateralValueInUsd = wethValue + wbtcValue;
        console.log("dsc supply: ", totalSupply);
        console.log("total collateral value: ", totalCollateralValueInUsd);

        // assert that total supply of dsc is less than the total value of collateral
        assert(totalSupply <= totalCollateralValueInUsd);
    }
}
