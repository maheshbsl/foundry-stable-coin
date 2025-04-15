// SPDX-License-Identifier:MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployKey;
    }

    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant WBTC_USD_PRICE = 40000e8;
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaNetworkConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilNetworkConfig();
        }
    }

    // get sepolia networkConfig
    function getSepoliaNetworkConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployKey: 0
        });

        return sepoliaConfig;
    }

    function getOrCreateAnvilNetworkConfig() public returns (NetworkConfig memory) {
        // if we already have an avtive networkconfig return that
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        // otherwise deploy a new priceFeed
        vm.startBroadcast();
        // deploy ethusd price feed
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        // deploy weth toeken
        ERC20Mock wethMock = new ERC20Mock();
        //  deploy wbtcusd price feed
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, WBTC_USD_PRICE);
        // deploy wbtc token
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();

        // set the active network config
        NetworkConfig memory anvilConfig = NetworkConfig({
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployKey: DEFAULT_ANVIL_KEY
        });

        return anvilConfig;
    }
}
