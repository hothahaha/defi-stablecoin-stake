// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {DeployScript} from "../../script/Deploy.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {API3Feed} from "../../src/price-feeds/API3Feed.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployScript deployer;
    DSCEngine engine;
    DecentralizedStableCoin msc;
    MockERC20 weth;
    MockERC20 usdc;
    address ethUsdPriceFeed;
    address usdcUsdPriceFeed;
    uint256 deployerKey;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 100 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    int256 public constant ETH_USD_PRICE = 2000e18;
    int256 public constant USDC_USD_PRICE = 1e18;

    function setUp() public {
        deployer = new DeployScript();
        DeployScript.NetworkConfig memory networkConfig = deployer.getNetworkConfig();
        address[] memory collateralTokens = networkConfig.collateralTokens;
        address[] memory priceFeeds = networkConfig.priceFeeds;

        // Set tokens and price feeds
        weth = MockERC20(collateralTokens[0]);
        usdc = MockERC20(collateralTokens[1]);

        ethUsdPriceFeed = priceFeeds[0];
        usdcUsdPriceFeed = priceFeeds[1];

        deployerKey = networkConfig.deployerKey;

        // 部署 DSC 和 Engine
        msc = new DecentralizedStableCoin("Mantle Stable Coin", "DSC");
        engine = new DSCEngine(collateralTokens, priceFeeds, address(msc));

        // 设置权限
        msc.updateMinter(address(engine), true);

        // 给用户一些代币
        vm.prank(USER);
        weth.mint(STARTING_USER_BALANCE);
        usdc.mint(STARTING_USER_BALANCE);
    }

    /////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15 ether;
        uint256 expectedUsd = 30000e18; // 1 ETH = 2000 USD
        uint256 actualUsd = engine.getUsdValue(address(weth), ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetUsdValueOfUsdc() public view {
        uint256 usdcAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(address(weth), usdcAmount);
        assertEq(actualWeth, expectedWeth);
    }

    /////////////////////////////
    // DepositCollateral Tests //
    /////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        weth.approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(address(weth), 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        MockERC20 randomToken = new MockERC20("Random", "RND");
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        weth.approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(address(weth), AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedCollateralValueInUsd = engine.getUsdValue(address(weth), AMOUNT_COLLATERAL);
        assertEq(totalDSCMinted, 0);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testEmitsEventOnCollateralDeposit() public {
        vm.startPrank(USER);
        weth.approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, true, address(engine));
        emit DSCEngine.CollateralDeposited(USER, address(weth), AMOUNT_COLLATERAL);

        engine.depositCollateral(address(weth), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        // 设置用户余额不足
        vm.startPrank(USER);
        weth.approve(address(engine), STARTING_USER_BALANCE * 2);
        vm.expectRevert();
        engine.depositCollateral(address(weth), STARTING_USER_BALANCE * 2);
        vm.stopPrank();
    }

    /////////////////////////////
    // RedeemCollateral Tests //
    /////////////////////////////

    function testRevertRedeemCollateralIfAmountZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(address(weth), 0);
        vm.stopPrank();
    }

    ////////////////
    // Mint Tests //
    ////////////////

    function testRevertsIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDSC(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        uint256 collateralValueInUsd = engine.getUsdValue(address(weth), AMOUNT_COLLATERAL);
        uint256 amountToMint = (collateralValueInUsd * 100) / LIQUIDATION_THRESHOLD + 1;
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        engine.mintDSC(amountToMint);
        vm.stopPrank();
    }

    function testMintEmitsEvent() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 100e18;

        vm.expectEmit(true, true, true, true, address(engine));
        emit DSCEngine.DSCMinted(USER, amountToMint);

        engine.mintDSC(amountToMint);
        vm.stopPrank();
    }

    ////////////////////
    // Liquidate Tests //
    ////////////////////

    function testCantLiquidateGoodHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        uint256 collateralValueInUsd = engine.getUsdValue(address(weth), AMOUNT_COLLATERAL);
        uint256 halfCollateralValueInUsd = collateralValueInUsd / 2;
        engine.mintDSC(halfCollateralValueInUsd);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(address(weth), USER, halfCollateralValueInUsd);
        vm.stopPrank();
    }

    function testLiquidationImproveHealthFactor() public {
        // 设置初始状态
        vm.startPrank(USER);
        weth.approve(address(engine), AMOUNT_COLLATERAL + (AMOUNT_COLLATERAL * 10) / 100); // 10% 的额外抵押
        engine.depositCollateral(address(weth), AMOUNT_COLLATERAL + (AMOUNT_COLLATERAL * 10) / 100); // 10% 的额外抵押
        uint256 collateralValueInUsd = engine.getUsdValue(address(weth), AMOUNT_COLLATERAL);
        uint256 amountToMint = (collateralValueInUsd * 50) / 100; // 50% 抵押率
        engine.mintDSC(amountToMint);
        vm.stopPrank();

        // 价格下跌 50%
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ETH_USD_PRICE / 2);

        // 准备清算
        msc.updateMinter(LIQUIDATOR, true);

        vm.startPrank(LIQUIDATOR);
        weth.mint(AMOUNT_COLLATERAL);
        weth.approve(address(engine), AMOUNT_COLLATERAL);
        msc.mint(LIQUIDATOR, amountToMint);
        msc.approve(address(engine), amountToMint);

        // 记录清算前的余额
        uint256 liquidatorBalanceBefore = weth.balanceOf(LIQUIDATOR);

        // 清算
        engine.liquidate(address(weth), USER, amountToMint);
        vm.stopPrank();

        // 验证清算人获得的抵押品
        uint256 liquidatorBalanceAfter = weth.balanceOf(LIQUIDATOR);
        assertGt(liquidatorBalanceAfter, liquidatorBalanceBefore);

        // 验证健康因子已改善
        uint256 userHealthFactor = engine.getHealthFactor(USER);
        assertGt(userHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testRevertLiquidateIfAmountZero() public {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.liquidate(address(weth), USER, 0);
        vm.stopPrank();
    }

    // 添加健康因子计算测试
    function testHealthFactorCalculation() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 1000e18; // 铸造1000 DSC
        engine.mintDSC(amountToMint);

        uint256 healthFactor = engine.getHealthFactor(USER);
        // 验证健康因子在预期范围内
        assertGt(healthFactor, MIN_HEALTH_FACTOR);
        vm.stopPrank();
    }
}
