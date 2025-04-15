// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event DSCMinted(address indexed user, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );
    event DSCBurned(uint256 amountDscToBurn);

    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    DeployDSC deployer;
    HelperConfig helperConfig;

    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployKey;

    address user = makeAddr("user");

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();

        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TEST
    //////////////////////////////////////////////////////////////*/

    // test constructor is set up correctly
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfLengthOfTokenAddressesAndPriceFeedAddressesIsNotSame() public {
        // arrange
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        // act: deploy contract and expect to revert
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTES
    //////////////////////////////////////////////////////////////*/

    // test getUsdValue function
    function testGetUsdValue() public view {
        // arrange: we have to pass the token and tokeAmount
        uint256 tokenAmount = 1 ether;
        uint256 expectedValueInUsd = 2000e18;

        // act : call getUsdValue function
        uint256 valueInUsd = dscEngine.getUsdValue(weth, tokenAmount);

        // assert : we get the expected value
        assertEq(expectedValueInUsd, valueInUsd);
    }

    // test getTokenAmountFromUsd
    function testGetTokenAmountFromUsd() public view {
        // arrange:
        uint256 usdAmount = 2000 ether;
        uint256 expectedETHAmount = 1 ether;

        // act : call getTokenAmountFromUsd function
        uint256 tokenAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);

        // assert :
        assertEq(expectedETHAmount, tokenAmount);
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT COLLATERAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test collateral is deposited, state is updated, event is emitted
     */
    function testDepositCollateralSuccess() public {
        // arrange: need collateral token and amount
        vm.startPrank(user);
        uint256 amountCollateral = 3 ether;
        // give user some weth tokens
        ERC20Mock(weth).mint(user, amountCollateral);
        // allow engine to spend weth tokens
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);

        // act:  deposit the collateral, and expect the event
        vm.expectEmit(true, true, false, true);
        emit CollateralDeposited(user, weth, amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);

        // assert: state is updated
        uint256 amountDeposited = dscEngine.getCollateralAmount(user, weth);
        assertEq(amountDeposited, amountCollateral);

        // check the balance of the engine
        uint256 balanceOfEngine = ERC20Mock(weth).balanceOf(address(dscEngine));

        assertEq(balanceOfEngine, amountCollateral);
        vm.stopPrank();
    }

    // test depositCollateral reverts if zero amount
    function testDepositCollateralRevertsIfZeroAmount() public {
        // arrange:
        vm.startPrank(user);
        uint256 amountCollateral = 1 ether;
        // give some weth to user
        ERC20Mock(weth).mint(user, amountCollateral);
        // approve engine to user the tokens in behalf of user
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);

        // act: deposit collateral with amount 0 and expect for reverts
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    //test depositCollateralReverts if the token is not valid
    function testDepositCollateralRevertsIfTheTokenIsInvalid() public {
        // arrange : get a invalid token
        address randomToken = address(0x123);
        vm.startPrank(user);

        // act : deposit the invalid token and expect revert
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(randomToken, 1 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                MINT DSC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test dsc minting, state updates, event emission
     */

    // test mint dsc success

    function testMintDscSuccess() public {
        // arrange: to mint dsc you need to have collateral
        // let's deosit some collateral for the user first
        vm.startPrank(user);
        uint256 amountCollateral = 3 ether;
        ERC20Mock(weth).mint(user, amountCollateral);
        // approve dscEngine to use the tokens
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        // deposit collateral
        dscEngine.depositCollateral(weth, amountCollateral);

        // act : let's mint some dsc tokens for user and expect event to be emitted
        uint256 amountDscToMint = 500e18;
        vm.expectEmit(true, false, false, true);
        emit DSCMinted(user, amountDscToMint);
        dscEngine.mintDSC(amountDscToMint);

        // assert : state is updated
        uint256 amountDscMinted = dscEngine.getDscMinted(user);

        // amountDscMinted == amountDscToMint
        assertEq(amountDscMinted, amountDscToMint);

        // user should receive the dsc
        uint256 dscBalanceOfUser = dsc.balanceOf(user);

        // dscBalanceOfUser == amountDscToMint
        assertEq(dscBalanceOfUser, amountDscToMint);
    }

    // test mintDscReverts if health factor breaks
    function testMintDscRevertsIfHealthFactorBreak() public {
        // arrange : deposit collateral for user
        vm.startPrank(user);
        uint256 amountCollateral = 1 ether;
        ERC20Mock(weth).mint(user, amountCollateral);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);

        // act : mint too much dsc and expect the function to revert
        uint256 amountDscToMint = 3000e18;
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorBroken.selector);
        dscEngine.mintDSC(amountDscToMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                BURN DSC
    //////////////////////////////////////////////////////////////*/

    // test burnDsc success
    function testBurnDSCSuccess() public {
        // Arrange: deposit collateral, mint dsc
        uint256 amountCollateral = 0.5 ether; // 0.5 eth => 1000$ worth of collateral
        uint256 amountDscToMint = 200e18;
        vm.startPrank(user);

        // give user some tokens
        ERC20Mock(weth).mint(user, amountCollateral);
        // approve dscEngine to use tokens on behalf of user
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        // now deposit the collateral
        dscEngine.depositCollateral(weth, amountCollateral);
        // mint dsc for the user
        dscEngine.mintDSC(amountDscToMint); // now user has minted 200dsc

        // act : lets's try to burn them
        // approve dscEngine to use dsc on behalf of user
        dsc.approve(address(dscEngine), amountDscToMint);

        // let's burn 100 dsc, expect the event to be emitted
        uint256 amountDscToBurn = 100e18;
        vm.expectEmit(false, false, false, true);
        emit DSCBurned(amountDscToBurn);
        dscEngine.burnDSC(amountDscToBurn);

        // assert:
        uint256 remainingDsc = dscEngine.getDscMinted(user);
        assertEq(remainingDsc, 100e18);
        assertEq(dsc.balanceOf(user), (amountDscToMint - amountDscToBurn));

        uint256 dscBalanceOfEngine = dsc.balanceOf(address(dscEngine));

        assertEq(dscBalanceOfEngine, 0, "DSCEngine should have no DSC after burn");
    }

    // test burn dsc reverts if insufficient dsc
    function testBurnDSCRevertsIfDSCMintedInsufficient() public {
        // arrange : deposit collateral, mint usd
        vm.startPrank(user);
        uint256 amountCollateral = 0.5 ether;
        uint256 amountDscToMint = 200e18;

        //give user some weth to deposit collateral
        ERC20Mock(weth).mint(user, amountCollateral);
        // approve dscEngine to use the weth on behalf of user
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);

        // now deposit collateral
        dscEngine.depositCollateral(weth, amountCollateral);
        // mint dsc for user
        dscEngine.mintDSC(amountDscToMint); // user has now minted 200 dsc

        // act: let's try to burn 300 dsc which is greater than the amount minted and expect for reverts
        uint256 amountDscToBurn = 300e18;
        vm.expectRevert(DSCEngine.DSCEngine__InsufficientDSC.selector);
        dscEngine.burnDSC(amountDscToBurn);
    }

    /*//////////////////////////////////////////////////////////////
                           REDEEM COLLATERAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev A user with sufficient collateral and a healthy position (health factor > 1e18)
     *      after redemption can redeem their collateral
     * @dev Fails if the user tries to redeem more collateral than they have deposited
     * @dev Fails if their health factor would be broken after redemption
     */
    function testUserCanRedeemCollateral() public {
        // arrange : deposit collateral, mint dsc
        vm.startPrank(user);
        uint256 amountCollateral = 0.5 ether; // $1000 worth of collateral
        uint256 amountDscToMint = 200e18;

        // give user some token to deposit as collateral
        ERC20Mock(weth).mint(user, amountCollateral);
        // approve the engine can spend the tokens on behalf of user
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);

        // now deposit the collateral
        dscEngine.depositCollateral(weth, amountCollateral);
        // now we have collateral , can mint dsc
        dscEngine.mintDSC(amountDscToMint); //now  user has now minted 200 dsc

        // Act: let's redeem $600 worth of eth => 0.3 eth  (collateral left is 0.2 eth) which is 400$ and we have 200$ worth of dsc
        uint256 amountToRedeem = 0.3e18;
        // redeem and expect ro event
        vm.expectEmit(true, true, true, false);
        emit CollateralRedeemed(user, user, weth, amountToRedeem);
        dscEngine.redeemCollateral(weth, amountToRedeem);

        // Assert :
        uint256 collateralLeft = dscEngine.getCollateralAmount(user, weth);
        assertEq(collateralLeft, 0.2e18);

        uint256 wethBalanceOfUser = ERC20Mock(weth).balanceOf(user);
        assertEq(wethBalanceOfUser, 0.3e18); // redeemed 0.3
    }

    // challenge test reddeem collateral reverts if health factor broken

    function testRedeemCollateralRevertsIfHealthFactorBroken() public {
        // Arrange : deposit collateral, mint dsc
        vm.startPrank(user);
        uint256 amountCollateral = 0.5 ether;
        uint256 amountDscToMint = 200e18; // 200dsc

        // give user some tokens to deposit
        ERC20Mock(weth).mint(user, amountCollateral);
        // approve dscEngine to spend weth tokens on behalf of user
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);

        // now deposit the collateral
        dscEngine.depositCollateral(weth, amountCollateral); // deposited 0.5 ether => $1000
        // now mint dsc
        dscEngine.mintDSC(amountDscToMint); // 200 dsc minted for user

        // Act : user have 0.5 collateral balance , try to redeem all , except to revert
        uint256 amountToRedeem = 0.5 ether;
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorBroken.selector);
        dscEngine.redeemCollateral(weth, amountToRedeem);
    }

    /*//////////////////////////////////////////////////////////////
                            LIQUIDATION TEST
    //////////////////////////////////////////////////////////////*/

    // test liquidate success
    function testLiquidateSuccess() public {
        // Arrange : user, liquidator, and dscHolder (who will transfer dsc to liquidator)
        address liquidator = makeAddr("liquidator");
        address dscHolder = makeAddr("dscHolder");
        uint256 amountCollateral = 0.5 ether;
        uint256 amountDscToMint = 666e18;

        // User mints dsc
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, amountCollateral);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);
        dscEngine.mintDSC(amountDscToMint);
        vm.stopPrank();

        // DscHolder mint dsc to transfer to liquidator
        vm.startPrank(dscHolder);
        ERC20Mock(weth).mint(dscHolder, amountCollateral);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);
        dscEngine.mintDSC(amountDscToMint);
        vm.stopPrank();

        // dsc holder transfer dsc to liquidator
        uint256 debtToCover = 100e18; // 100dsc
        vm.startPrank(dscHolder);
        dsc.transfer(liquidator, debtToCover);
        vm.stopPrank();

        // the price to weth drops to $1500
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1500e8);
        // user new collateral value = 0.5 eth * 1500 => 750$
        // addjusted collateral = 750 * 0.67 = 502.5$
        // hf after price drop = 502.5 / 666 => 0.754 < 1
        // can trigger liquidate

        // liquidator approves dscEngine to use dsc tokens
        vm.startPrank(liquidator);
        dsc.approve(address(dscEngine), debtToCover);

        // Act : liquidator call liquidate functionc
        dscEngine.liquidate(weth, user, debtToCover);
    }

    /*//////////////////////////////////////////////////////////////
                          HEALTH FACTOR CHECK
    //////////////////////////////////////////////////////////////*/

    // test health factor is calculated correctly
    function testHealthFactorIsCalculatedCorrectly() public {
        // arrange : deposit collateral , mint dsc
        uint256 amountCollateral = 0.5 ether; // $1000
        uint256 amountDscToMint = 666e18;
        vm.startPrank(user);

        ERC20Mock(weth).mint(user, amountCollateral);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);
        dscEngine.mintDSC(amountDscToMint);

        // act: get the health factor
        // 1000 * 67 / 100 = 670
        // hf = 670 / 666 = 1.006
        uint256 expectedHealthFactor = 1_006006006006006006;
        uint256 actualHealthFactor = dscEngine.getHealthFactor(user);

        // assert : health factor is calculated correctly
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                         GETTER FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    // test get account collateral value
    function testGetAccountCollateralValue() public {
        // arrange : deposit collateral , mint dsc
        uint256 amountCollateral = 0.5 ether; // $1000
        uint256 amountDscToMint = 666e18;
        vm.startPrank(user);

        ERC20Mock(weth).mint(user, amountCollateral);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);
        dscEngine.mintDSC(amountDscToMint);

        // act : get the account collateral value
        uint256 expectedAccountCollateralValue = 1000e18;
        uint256 actualAccountCollateralValue = dscEngine.getAccountCollateralValue(user);

        // assert : account collateral value is calculated correctly
        assertEq(expectedAccountCollateralValue, actualAccountCollateralValue);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT COLLATERARL AND MINT DSC
    //////////////////////////////////////////////////////////////*/

    // test deposit collateral and mint dsc
    function testDepositAndMintDsc() public {
        // arrange : deposit collateral , mint dsc
        uint256 amountCollateral = 0.5 ether; // $1000
        uint256 amountDscToMint = 666e18;
        vm.startPrank(user);

        ERC20Mock(weth).mint(user, amountCollateral);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(weth, amountCollateral, amountDscToMint);

        uint256 expectedAccountCollateralValue = 1000e18;
        uint256 actualAccountCollateralValue = dscEngine.getAccountCollateralValue(user);

        // assert : account collateral value is calculated correctly
        assertEq(expectedAccountCollateralValue, actualAccountCollateralValue);
    }

    // test redeem collateral for dsc
    function testRedeemCollateralForDsc() public {
        // arrange : deposit collateral , mint dsc

        uint256 amountCollateral = 0.5 ether; // $1000
        uint256 amountDscToMint = 300e18;
        vm.startPrank(user);

        ERC20Mock(weth).mint(user, amountCollateral);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(weth, amountCollateral, amountDscToMint);

        // act : redeem collateral for dsc
        uint256 amountCollateralToRedeem = 0.1 ether;
        uint256 amountDscToBurn = 100e18;
        dsc.approve(address(dscEngine), amountDscToBurn);
        dscEngine.redeemCollateralForDsc(weth, amountCollateralToRedeem, amountDscToBurn);
    }
}
