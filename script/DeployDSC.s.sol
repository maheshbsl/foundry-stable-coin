// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public priceFeeedAddresses;
    address[] public tokenAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployKey) =
            helperConfig.activeNetworkConfig();

        priceFeeedAddresses.push(wethUsdPriceFeed);
        priceFeeedAddresses.push(wbtcUsdPriceFeed);

        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);

        vm.startBroadcast(deployKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeeedAddresses, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dsc, dscEngine, helperConfig);
    }
}
