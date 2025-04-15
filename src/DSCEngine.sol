// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier:MIT

pragma solidity ^0.8.28;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author maheshbsl
 * @dev This system is designed to be as minimal as possible.
 *
 * It is similar to DAI if DAI had no governance , no fees and was only based by WETH and WBTC.
 *
 * @dev This contract is the core of the DSC system. It is responsible for the following:
 * - Collateral management
 * - Minting and burning of DSC
 * - Liquidation of undercollateralized positions
 * - Managing the collateralization ratio
 * - Managing the liquidation ratio
 *
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__MustBeGreaterThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken();
    error DSCEngine__MintFailed();
    error DSCEngine__InsufficientCollateral();
    error DSCEngine__InsufficientDSC();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant ADDTIONAL_FEED_PRICISION = 1e10; // 10**10
    uint256 private constant LIQUIDATION_THRESHOLD = 67; // must be 200% over collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant ADDTIONAL_PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1.0
    uint256 private constant LIQUIDATION_BONUS = 10; // this means 10% bonus

    mapping(address token => address priceFeed) public s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) public s_collateralDeposited;
    mapping(address user => uint256 amount) public s_dscMinted;
    address[] public s_allowedTokens;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event DSCMinted(address indexed user, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );
    event DSCBurned(uint256 amountDscToBurn);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev  This modifier is used to check if the amount is greater than zero.
     */
    modifier moreThanZero(uint256 amount) {
        require(amount > 0, DSCEngine__MustBeGreaterThanZero());
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_allowedTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) public {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @dev This function is used to deposit collateral into the system.
     * @param tokenCollateralAddress - The address of the collateral token.
     * @param amountCollateral - The amount of collateral to deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // update the states
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // transfer the collateral to the contract
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        require(success, DSCEngine__TransferFailed());
        // emit the event
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    }
    /**
     * @dev In order to redeem collateral,
     * healthfactor must be over 1 after collateral pulled
     */

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        // follow CEI
        // use must have enough collateral to redeem
        require(
            s_collateralDeposited[msg.sender][tokenCollateralAddress] >= amountCollateral,
            DSCEngine__InsufficientCollateral()
        );

        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);

        // check if withdrawal will break the healthFactor
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateralForDsc(address tokenCollateralAddres, uint256 amountCollateral, uint256 amountDscToBurn)
        public
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddres, amountCollateral);
    }

    /**
     * @dev This function is used to mint DSC.
     *
     * @param amountDscToMint  The amount of DSC to mint.
     *
     * Requirements:
     * -amountDscToMint must be greater than zero.
     * - The caller must have enough collateral to mint the DSC.
     */
    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        // updates the states
        s_dscMinted[msg.sender] += amountDscToMint;

        // if they minted too much dsc
        _revertIfHealthFactorIsBroken(msg.sender);

        // other wise mint the dsc for user
        bool success = i_dsc.mint(msg.sender, amountDscToMint);
        require(success, DSCEngine__MintFailed());

        // emit the event
        emit DSCMinted(msg.sender, amountDscToMint);
    }

    function burnDSC(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        // make sure there is enough dsc to burn
        require(s_dscMinted[msg.sender] >= amountDscToBurn, DSCEngine__InsufficientDSC());

        _burnDSC(amountDscToBurn, msg.sender, msg.sender);
    }
    // If someone is almost undercollateralized , we will pay you to liquidate them
    /**
     * @param tokenCollateralAddress - The address of the collateral token to liquidate from the user
     * @param user - The user who has broken the health factor,
     * @param debtToCover - The amount of dsc you want to burn to improve the user health factor
     *
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the user funds
     *
     * @dev This function working assumes the protocol will be roughly 200% overcollateralized
     * in order for this to work
     *
     * @notice A known bug would be if the protocol were 100% or less collateralized,
     * then we wouldn't be able to incentive the liquidators.
     *
     * @dev Follow CEI, check ,
     *
     * we should only liquidate people who is liquidatable
     *
     */

    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        public
        moreThanZero(debtToCover)
        nonReentrant
    {
        // need to check the health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);

        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // we want to burn their DSC debt
        // and take their collateral
        // bad user => $140 eth , $100 dsc
        // debt to cover => $100
        // $100 of dsc == ? eth
        // so if the price of eth is $2000 then $100 of dsc would be 0.05 eth

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
        // and give them a 10% bonus
        // so we are giving the liquidator $110 of weth for 100 dsc
        // 0.05 eth * 0.1 = 0.005 eth = this is bonus collateral
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        // redeem the collateral
        _redeemCollateral(tokenCollateralAddress, totalCollateralToRedeem, user, msg.sender);

        // burn the dsc
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // if liquidating doesn't improve the health factor reverts
        require(endingUserHealthFactor > startingUserHealthFactor, DSCEngine__HealthFactorNotImproved());

        // we will reverts if the liquidator's health factor is broken by this process
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        internal
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        require(success, DSCEngine__TransferFailed());

        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
    }

    function _burnDSC(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) internal {
        // update the state
        s_dscMinted[onBehalfOf] -= amountDscToBurn;

        // transfer the dsc from the liquidator to the contract
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        require(success, DSCEngine__TransferFailed());

        // burn the dsc
        i_dsc.burn(amountDscToBurn);

        // emit the event
        emit DSCBurned(amountDscToBurn);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // check health factor (if they have enought collateral)
        // revert if they don't
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBroken();
        }
    }

    /**
     * @param user The address of the user to check the health factor for.
     * @return The health factor of the user.
     * @dev Returns how close to liquidation the user is.
     */
    function _healthFactor(address user) internal view returns (uint256) {
        // we will need total collateral value, total dsc minted
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        // If no DSC is minted, return max health factor
        if (totalDscMinted == 0) {
            return type(uint256).max; // Return maximum value for safe health factor
        }
        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * ADDTIONAL_PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        // total dsc minted
        totalDscMinted = s_dscMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValue(user);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited,
        // map it to the price to get the usd value
        for (uint256 i = 0; i < s_allowedTokens.length; i++) {
            address token = s_allowedTokens[i];
            uint256 tokenAmount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, tokenAmount);
        }
    }

    function getUsdValue(address token, uint256 tokenAmount) public view returns (uint256) {
        // get the priceFeed
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // price comes with 8 decimals so multiply by 10**10
        uint256 priceInUsd = uint256(price) * ADDTIONAL_FEED_PRICISION;
        return (priceInUsd * tokenAmount) / ADDTIONAL_PRECISION;
    }

    function getCollateralAmount(address user, address tokenCollateralAddress) public view returns (uint256) {
        return s_collateralDeposited[user][tokenCollateralAddress];
    }

    function getDscMinted(address user) public view returns (uint256) {
        return s_dscMinted[user];
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // get the priceFeed
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // price comes with 8 decimals so multiply by 10**10 // 2000e8 * 1e10 => 2000e18
        uint256 priceInUsd = uint256(price) * ADDTIONAL_FEED_PRICISION;
        return (usdAmountInWei * ADDTIONAL_PRECISION) / priceInUsd;
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_allowedTokens;
    }

}
