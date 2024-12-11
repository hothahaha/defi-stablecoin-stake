// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {DeployScript} from "../../script/Deploy.s.sol";
import {LendingPool} from "../../src/LendingPool.sol";
import {InsurancePool} from "../../src/InsurancePool.sol";
import {AssetManager} from "../../src/AssetManager.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {InterestRateModel} from "../../src/libraries/InterestRateModel.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract LendingPoolTest is Test {
    DeployScript deployer;
    LendingPool pool;
    InsurancePool insurancePool;
    AssetManager assetManager;
    MockERC20 weth;
    MockERC20 usdc;
    address ethUsdPriceFeed;
    address usdcUsdPriceFeed;
    DecentralizedStableCoin dsc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant INITIAL_DEPOSIT = 20 ether;
    uint256 public constant REWARD_PER_BLOCK = 1e18;
    uint256 public constant ETH_PRICE = 2000e8;
    uint256 public constant USDC_PRICE = 1e8;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;

    function setUp() public {
        // 部署mock tokens
        deployer = new DeployScript();
        DeployScript.NetworkConfig memory networkConfig = deployer.getNetworkConfig();
        address[] memory tokens = networkConfig.collateralTokens;
        address[] memory priceFeeds = networkConfig.priceFeeds;

        // Set tokens and price feeds
        weth = MockERC20(tokens[0]);
        usdc = MockERC20(tokens[1]);

        ethUsdPriceFeed = priceFeeds[0];
        usdcUsdPriceFeed = priceFeeds[1];

        // 部署相关合约
        insurancePool = new InsurancePool();
        assetManager = new AssetManager();
        dsc = new DecentralizedStableCoin("Decentralized Stable Coin", "DSC");

        // 部署 lending pool
        pool = new LendingPool(
            address(insurancePool),
            address(dsc),
            REWARD_PER_BLOCK,
            address(assetManager),
            tokens,
            priceFeeds
        );

        assetManager.setLendingPool(address(pool));
        assetManager.updateAddRole(address(pool), true);
        dsc.updateMinter(address(pool), true);

        for (uint i = 0; i < tokens.length; i++) {
            string memory symbol = i == 0 ? "WETH" : "USDC";
            string memory name = i == 0 ? "Wrapped ETH" : "USD Coin";
            uint8 decimals = i == 0 ? 18 : 6;
            string memory icon = i == 0
                ? "https://assets.coingecko.com/coins/images/279/small/ethereum.png"
                : "https://assets.coingecko.com/coins/images/6319/small/USD_Coin_icon.png";

            AssetManager.AssetConfig memory assetConfig = AssetManager.AssetConfig({
                isSupported: true,
                collateralFactor: 75e16, // 75%
                borrowFactor: 80e16, // 80%
                symbol: symbol,
                name: name,
                decimals: decimals,
                icon: icon
            });
            assetManager.addAsset(tokens[i], assetConfig);
        }

        // 借贷池中金额初始化
        weth.mint(INITIAL_DEPOSIT);
        weth.transfer(address(pool), INITIAL_DEPOSIT);
        usdc.mint(INITIAL_DEPOSIT * 2000);
        usdc.transfer(address(pool), INITIAL_DEPOSIT * 2000);

        // 设置初始状态
        vm.startPrank(USER);
        weth.mint(INITIAL_DEPOSIT);
        usdc.mint(INITIAL_DEPOSIT * 2000);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        // 设置 liquidator
        vm.startPrank(LIQUIDATOR);
        weth.mint(INITIAL_DEPOSIT);
        usdc.mint(INITIAL_DEPOSIT * 2000);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function testInitialState() public view {
        assertEq(address(pool.dsc()), address(dsc));
        assertEq(address(pool.insurancePool()), address(insurancePool));
        assertEq(address(pool.assetManager()), address(assetManager));
    }

    function testDeposit() public {
        vm.startPrank(USER);
        uint256 depositAmount = 1 ether;

        pool.deposit(address(weth), depositAmount);

        (uint128 userDeposit, , , , , ) = pool.userInfo(address(weth), USER);
        assertEq(userDeposit, depositAmount);
        vm.stopPrank();
    }

    /////////////
    // Deposit //
    /////////////
    function testDepositZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(LendingPool.LendingPool__InvalidAmount.selector);
        pool.deposit(address(weth), 0);
        vm.stopPrank();
    }

    function testMultipleDepositsAndWithdraws() public {
        vm.startPrank(USER);

        // 多次存款
        pool.deposit(address(weth), 1 ether);
        pool.deposit(address(weth), 0.5 ether);
        pool.deposit(address(weth), 0.3 ether);

        // 记录总存款金额
        (uint128 totalDeposit, , , , , ) = pool.userInfo(address(weth), USER);

        // 部分提款
        pool.withdraw(address(weth), 0.8 ether);

        // 验证剩余金额
        (uint128 remainingDeposit, , , , , ) = pool.userInfo(address(weth), USER);
        assertEq(remainingDeposit, totalDeposit - 0.8 ether);

        vm.stopPrank();
    }

    function testDepositWithZeroTotalDeposits() public {
        vm.startPrank(USER);

        // 确保总存款为0
        (uint256 totalDeposits, , , , , , , , ) = pool.assetInfo(address(weth));
        assertEq(totalDeposits, 0);

        // 首次存款
        pool.deposit(address(weth), 1 ether);

        // 验证奖励计算正确初始化
        uint256 accRewardPerShare = pool.getAccRewardPerShare(address(weth));
        assertEq(accRewardPerShare, 0);

        vm.stopPrank();
    }

    ////////////
    // Borrow //
    ////////////
    function testBorrow() public {
        // 先存款
        vm.startPrank(USER);
        uint256 depositAmount = 1 ether;
        pool.deposit(address(weth), depositAmount);

        // 再借款
        uint256 borrowAmount = 0.5 ether;
        pool.borrow(address(usdc), borrowAmount);

        (, uint128 userBorrow, , , , ) = pool.userInfo(address(usdc), USER);
        assertEq(userBorrow, borrowAmount);
        vm.stopPrank();
    }

    function testMaximumBorrowLimit() public {
        vm.startPrank(USER);
        pool.deposit(address(weth), 10 ether);
        console.log("collateral value: ", pool.getCollateralValue(USER));
        // 尝试超额借款
        uint256 maxBorrow = pool.getUserBorrowLimit(USER, address(usdc));
        console.log("maxBorrow: ", maxBorrow);
        vm.expectRevert(LendingPool.LendingPool__ExceedsMaxBorrowFactor.selector);
        pool.borrow(address(usdc), maxBorrow + 1);
        vm.stopPrank();
    }

    ///////////
    // Repay //
    ///////////
    function testRepay() public {
        // Setup: deposit and borrow first
        vm.startPrank(USER);
        pool.deposit(address(weth), 1 ether);
        uint256 borrowAmount = 0.5 ether;
        pool.borrow(address(usdc), borrowAmount);

        // Repay the borrowed amount
        pool.repay(address(usdc), borrowAmount);

        (, uint128 userBorrow, , , , ) = pool.userInfo(address(usdc), USER);
        assertEq(userBorrow, 0);
        vm.stopPrank();
    }

    //////////////
    // Withdraw //
    //////////////
    function testWithdraw() public {
        // Setup: deposit first
        vm.startPrank(USER);
        uint256 depositAmount = 1 ether;
        pool.deposit(address(weth), depositAmount);

        // Withdraw half
        uint256 withdrawAmount = depositAmount / 2;
        pool.withdraw(address(weth), withdrawAmount);

        (uint128 userDeposit, , , , , ) = pool.userInfo(address(weth), USER);
        assertEq(userDeposit, withdrawAmount);
        vm.stopPrank();
    }

    function testWithdrawExceedsBalance() public {
        vm.startPrank(USER);
        pool.deposit(address(weth), 1 ether);

        vm.expectRevert(LendingPool.LendingPool__InsufficientBalance.selector);
        pool.withdraw(address(weth), 2 ether);
        vm.stopPrank();
    }

    ////////////
    // Reward //
    ////////////
    function testRewardAccrual() public {
        vm.startPrank(USER);
        pool.deposit(address(weth), 1 ether);

        // 推进区块
        vm.roll(block.number + 2);

        console.log("accRewardPerShare", pool.getAccRewardPerShare(address(weth)));
        // 领取奖励
        pool.claimReward(address(weth));

        // 验证奖励
        assertGt(dsc.balanceOf(USER), 0);
        vm.stopPrank();
    }

    function testRewardDistribution() public {
        // 多用户存款场景
        address[] memory users = new address[](3);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");

        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            weth.mint(INITIAL_DEPOSIT);
            weth.approve(address(pool), INITIAL_DEPOSIT);
            pool.deposit(address(weth), 1 ether);
            vm.stopPrank();
        }

        // 时间推进
        vm.roll(block.number + 1000);

        // 验证奖励分配
        for (uint i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            pool.claimReward(address(weth));
            assertGt(dsc.balanceOf(users[i]), 0);
        }
    }

    function testRewardAccrualWithTimeWeight() public {
        vm.startPrank(USER);

        // 第一次存款
        pool.deposit(address(weth), 1 ether);

        // 等待7天并领取第一次奖励
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 100);
        pool.claimReward(address(weth));
        uint256 firstReward = dsc.balanceOf(USER);

        // 追加存款
        pool.deposit(address(weth), 0.5 ether);

        // 再等7天并领取第二次奖励
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 100);
        pool.claimReward(address(weth));
        uint256 secondReward = dsc.balanceOf(USER) - firstReward;

        // 验证第二次奖励大于第一次（因为存款金额更多）
        assertGt(secondReward, firstReward);
        vm.stopPrank();
    }

    function testRewardCalculationPrecision() public {
        vm.startPrank(USER);

        // 存入一个很小的金额
        uint256 smallDeposit = 1 wei;
        pool.deposit(address(weth), smallDeposit);

        // 推进大量区块
        vm.roll(block.number + 1000000);

        // 领取奖励
        pool.claimReward(address(weth));

        // 验证即使是小额存款也能获得奖励
        assertGt(dsc.balanceOf(USER), 0);

        vm.stopPrank();
    }

    ////////////////
    // Collateral //
    ///////////////
    function testCollateralValue() public {
        vm.startPrank(USER);
        uint256 depositAmount = 1 ether;
        pool.deposit(address(weth), depositAmount);

        uint256 collateralValue = pool.getCollateralValue(USER);
        // Expected value: 1 ETH * $2000 * collateralFactor = $1500
        assertEq(collateralValue, ((depositAmount * uint256(ETH_PRICE) * 3) * 1e10) / (4 * 1e18));
        vm.stopPrank();
    }

    //////////////////
    // Interactions //
    //////////////////
    function testMultipleUsersInteractions() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        // 给用户代币
        vm.startPrank(user1);
        weth.mint(INITIAL_DEPOSIT);
        usdc.mint(INITIAL_DEPOSIT * 2000);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        weth.mint(INITIAL_DEPOSIT);
        usdc.mint(INITIAL_DEPOSIT * 2000);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        // User1 存款
        vm.prank(user1);
        pool.deposit(address(weth), 1 ether);

        // User2 存款
        vm.prank(user2);
        pool.deposit(address(usdc), 2000e18);

        // User1 借款
        vm.prank(user1);
        pool.borrow(address(usdc), 500e18);

        // User2 借款
        vm.prank(user2);
        pool.borrow(address(weth), 0.1 ether);

        // 验证状态
        (uint128 user1Deposit, uint128 user1Borrow, , , , ) = pool.userInfo(address(weth), user1);
        (uint128 user2Deposit, uint128 user2Borrow, , , , ) = pool.userInfo(address(usdc), user2);

        assertEq(user1Deposit, 1 ether);
        assertEq(user2Deposit, 2000e18);
        assertEq(user1Borrow, 0);
        assertEq(user2Borrow, 0);
    }

    ///////////
    // Asset //
    ///////////
    function testAddAsset() public {
        // 创建新的测试代币和价格源
        MockERC20 newToken = new MockERC20("Test Token", "TEST");
        MockV3Aggregator newPriceFeed = new MockV3Aggregator(8, 1000e8); // $1000 price

        // 设置资产配置
        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16, // 75%
            borrowFactor: 80e16, // 80%
            symbol: "TEST",
            name: "Test Token",
            decimals: 18,
            icon: "https://test.icon"
        });

        // 非管理员不能添加资产
        vm.startPrank(USER);
        vm.expectRevert();
        pool.addAsset(address(newToken), address(newPriceFeed), config);
        vm.stopPrank();

        // 管理员添加资产
        pool.addAsset(address(newToken), address(newPriceFeed), config);

        // 验证资产是否正确添加
        assertTrue(assetManager.isAssetSupported(address(newToken)), "Asset should be supported");

        // 验证资产配置
        AssetManager.AssetConfig memory savedConfig = assetManager.getAssetConfig(
            address(newToken)
        );
        assertEq(savedConfig.collateralFactor, config.collateralFactor);
        assertEq(savedConfig.borrowFactor, config.borrowFactor);
        assertEq(savedConfig.symbol, config.symbol);

        // 验证 LendingPool 中的资产信息
        LendingPool.AssetInfo memory assetInfo = pool.getAssetInfo(address(newToken));
        assertEq(assetInfo.totalDeposits, 0);
        assertEq(assetInfo.totalBorrows, 0);
        assertEq(assetInfo.lastUpdateTime, block.timestamp);
        assertEq(assetInfo.reserveFactor, 1e17); // 10% 储备金率
        assertEq(assetInfo.borrowIndex, 1e18); // 初始指数
        assertEq(assetInfo.depositIndex, 1e18); // 初始指数
    }

    function testAddAssetWithInvalidAddress() public {
        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16,
            borrowFactor: 80e16,
            symbol: "TEST",
            name: "Test Token",
            decimals: 18,
            icon: "https://test.icon"
        });

        // 测试零地址
        vm.expectRevert(LendingPool.LendingPool__InvalidAddress.selector);
        pool.addAsset(address(0), address(1), config);

        vm.expectRevert(LendingPool.LendingPool__InvalidAddress.selector);
        pool.addAsset(address(1), address(0), config);
    }

    function testAddDuplicateAsset() public {
        // 尝试添加已存在的 WETH
        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16,
            borrowFactor: 80e16,
            symbol: "WETH",
            name: "Wrapped ETH",
            decimals: 18,
            icon: "https://test.icon"
        });

        vm.expectRevert(); // 应该revert，因为资产已存在
        pool.addAsset(address(weth), ethUsdPriceFeed, config);
    }

    function testAddAssetAndDeposit() public {
        // 创建新代币和价格源
        MockERC20 newToken = new MockERC20("Test Token", "TEST");
        MockV3Aggregator newPriceFeed = new MockV3Aggregator(8, 1000e8);

        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16,
            borrowFactor: 80e16,
            symbol: "TEST",
            name: "Test Token",
            decimals: 18,
            icon: "https://test.icon"
        });

        // 添加资产
        pool.addAsset(address(newToken), address(newPriceFeed), config);

        // 为用户铸造代币并授权
        vm.startPrank(USER);
        newToken.mint(10 ether);
        newToken.approve(address(pool), type(uint256).max);

        // 测试存款
        pool.deposit(address(newToken), 1 ether);

        // 验证存款
        (uint128 userDeposit, , , , , ) = pool.userInfo(address(newToken), USER);
        assertEq(userDeposit, 1 ether, "Deposit amount mismatch");

        vm.stopPrank();
    }

    function testAddAssetAndBorrow() public {
        // 创建新代币和价格源
        MockERC20 newToken = new MockERC20("Test Token", "TEST");
        MockV3Aggregator newPriceFeed = new MockV3Aggregator(8, 1000e8);

        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16,
            borrowFactor: 80e16,
            symbol: "TEST",
            name: "Test Token",
            decimals: 18,
            icon: "https://test.icon"
        });

        // 添加资产
        pool.addAsset(address(newToken), address(newPriceFeed), config);

        // 为借贷池铸造初始流动性
        newToken.mint(100 ether);
        newToken.transfer(address(pool), 100 ether);

        vm.startPrank(USER);
        // 存入 WETH 作为抵押
        pool.deposit(address(weth), 10 ether);

        // 尝试借新代币
        uint256 borrowAmount = 5 ether;
        pool.borrow(address(newToken), borrowAmount);

        // 验证借款
        (, uint128 userBorrow, , , , ) = pool.userInfo(address(newToken), USER);
        assertEq(userBorrow, borrowAmount, "Borrow amount mismatch");

        vm.stopPrank();
    }

    ////////////////
    // Edge Cases //
    ////////////////
    function testEdgeCaseScenarios() public {
        // 测试零值转账
        vm.startPrank(USER);
        vm.expectRevert(LendingPool.LendingPool__InvalidAmount.selector);
        pool.deposit(address(weth), 0);

        // 测试未授权资产
        MockERC20 invalidToken = new MockERC20("Invalid", "INV");
        vm.expectRevert(LendingPool.LendingPool__AssetNotSupported.selector);
        pool.deposit(address(invalidToken), 1 ether);

        // 测试超额提款
        pool.deposit(address(weth), 1 ether);
        vm.expectRevert(LendingPool.LendingPool__InsufficientBalance.selector);
        pool.withdraw(address(weth), 2 ether);
        vm.stopPrank();
    }

    function testPause() public {
        pool.pause();

        vm.startPrank(USER);
        vm.expectRevert();
        pool.deposit(address(weth), 1 ether);
        vm.stopPrank();
    }

    function testUnpause() public {
        pool.pause();
        pool.unpause();

        vm.startPrank(USER);
        pool.deposit(address(weth), 1 ether);
        (uint128 userDeposit, , , , , ) = pool.userInfo(address(weth), USER);
        assertEq(userDeposit, 1 ether);
        vm.stopPrank();
    }

    function testEmergencyScenarios() public {
        // 测试暂停功能
        pool.pause();

        vm.startPrank(USER);
        vm.expectRevert();
        pool.deposit(address(weth), 1 ether);

        vm.expectRevert();
        pool.borrow(address(usdc), 100e18);
        vm.stopPrank();

        // 恢复并验证功能正常
        pool.unpause();
        vm.prank(USER);
        pool.deposit(address(weth), 1 ether);
    }

    /////////////////
    // Index Tests //
    /////////////////
    function testIndexAccrual() public {
        vm.startPrank(USER);

        // 初始存款
        uint256 depositAmount = 10 ether;
        pool.deposit(address(weth), depositAmount);

        // 记录初始指数
        (, , , , , , , uint256 initialBorrowIndex, uint256 initialDepositIndex) = pool.assetInfo(
            address(weth)
        );
        // 确保有借款以产生利息
        pool.borrow(address(weth), 5 ether); // 添加借款以产生利率

        // 时间推进
        vm.warp(block.timestamp + 365 days);
        // 触发指数更新
        pool.deposit(address(weth), 0.1 ether);

        // 获取更新后的指数
        (, , , , , , , uint256 newBorrowIndex, uint256 newDepositIndex) = pool.assetInfo(
            address(weth)
        );

        // 验证指数增长
        assertGt(newDepositIndex, initialDepositIndex, "Deposit index should increase");
        assertGt(newBorrowIndex, initialBorrowIndex, "Borrow index should increase");

        vm.stopPrank();
    }

    function testUserIndexUpdate() public {
        vm.startPrank(USER);

        // 存款和借款
        pool.deposit(address(usdc), 2000e18);
        pool.borrow(address(usdc), 1000e18);

        // 记录初始用户指数
        (, , , , uint256 initialUserBorrowIndex, uint256 initialUserDepositIndex) = pool.userInfo(
            address(usdc),
            USER
        );

        // 时间推进
        vm.warp(block.timestamp + 180 days);

        // 触发更新
        pool.borrow(address(usdc), 100e18);
        pool.deposit(address(usdc), 100e18);

        // 获取更新后的用户指数
        (, , , , uint256 newUserBorrowIndex, uint256 newUserDepositIndex) = pool.userInfo(
            address(usdc),
            USER
        );

        // 验证用户指数更新
        assertGt(newUserBorrowIndex, initialUserBorrowIndex, "User borrow index should update");
        assertGt(newUserDepositIndex, initialUserDepositIndex, "User deposit index should update");

        vm.stopPrank();
    }

    //////////////////////
    // Interest Tests //
    ////////////////////
    function testInterestAccrual() public {
        vm.startPrank(USER);

        // 初始存款和借款设置
        uint256 depositAmount = 10 ether;
        uint256 borrowAmount = 5 ether;
        pool.deposit(address(weth), depositAmount);
        pool.borrow(address(weth), borrowAmount);

        // 记录初始状态
        (uint128 initialDeposit, , , , , ) = pool.userInfo(address(weth), USER);
        (, , , , uint256 borrowRate, , , , ) = pool.assetInfo(address(weth));

        // 时间推进10天
        uint256 timeElapsed = 10 days;
        vm.warp(block.timestamp + timeElapsed);

        // 触发利息计算
        pool.deposit(address(weth), 1);

        // 获取更新后的状态
        (uint128 newDeposit, , , , , ) = pool.userInfo(address(weth), USER);

        // 计算预期利息
        uint256 expectedBorrowInterest = InterestRateModel.calculateInterest(
            borrowAmount,
            borrowRate,
            timeElapsed
        );
        uint256 reserveAmount = (expectedBorrowInterest * 1e17) / 1e18; // 10% 储备金率
        uint256 expectedDepositInterest = expectedBorrowInterest - reserveAmount;
        uint256 expectedNewDeposit = initialDeposit + expectedDepositInterest;

        // 验证实际利息是否在预期范围内（允许1% 误差）
        uint256 tolerance = (expectedNewDeposit * 1e16) / 1e18; // 1% tolerance
        console.log("tolerance: ", tolerance);
        assertApproxEqAbs(
            newDeposit,
            expectedNewDeposit,
            tolerance,
            "Deposit interest calculation mismatch"
        );

        vm.stopPrank();
    }

    function testBorrowInterestAccrual() public {
        vm.startPrank(USER);

        // 初始设置
        pool.deposit(address(usdc), 20000e18); // 充足的抵押
        uint256 borrowAmount = 1000e18;
        pool.borrow(address(usdc), borrowAmount);

        // 记录初始状态
        (, uint128 initialBorrow, , , , ) = pool.userInfo(address(usdc), USER);
        (, , , , uint256 borrowRate, , , , ) = pool.assetInfo(address(usdc));

        // 时间推进10天
        uint256 timeElapsed = 10 days;
        vm.warp(block.timestamp + timeElapsed);

        // 触发利息计算
        pool.borrow(address(usdc), 1);

        // 获取更新后的状态
        (, uint128 newBorrow, , , , ) = pool.userInfo(address(usdc), USER);

        // 计算预期借款利息
        uint256 expectedInterest = InterestRateModel.calculateInterest(
            initialBorrow,
            borrowRate,
            timeElapsed
        );
        uint256 expectedNewBorrow = initialBorrow + expectedInterest;

        // 验证实际借款是否在预期范围内（允许1% 误差）
        uint256 tolerance = (expectedNewBorrow * 1e16) / 1e18; // 1% tolerance
        assertApproxEqAbs(
            newBorrow,
            expectedNewBorrow,
            tolerance,
            "Borrow interest calculation mismatch"
        );

        vm.stopPrank();
    }

    function testGetUserRewardDebt() public {
        vm.startPrank(USER);

        // 存入资产以产生奖励债务
        pool.deposit(address(weth), 5 ether);
        pool.deposit(address(usdc), 10000e18);

        // 时间推进
        vm.warp(block.timestamp + 1 days);

        // 再次存入触发奖励更新
        pool.deposit(address(weth), 1);

        uint256 rewardDebt = pool.getUserRewardDebt(USER);
        assertGt(rewardDebt, 0, "Reward debt should be greater than 0");

        vm.stopPrank();
    }

    function testGetTotalValues() public {
        vm.startPrank(USER);
        pool.deposit(address(weth), 5 ether);
        pool.deposit(address(usdc), 10000e18);
        pool.borrow(address(weth), 2 ether);

        (uint256 totalDeposits, uint256 totalBorrows) = pool.getTotalValues();

        uint256 expectedDeposits = (5 ether * ETH_PRICE * ADDITIONAL_FEED_PRECISION) /
            PRECISION +
            (10000e18 * USDC_PRICE * ADDITIONAL_FEED_PRECISION) /
            PRECISION;
        uint256 expectedBorrows = (2 ether * ETH_PRICE * ADDITIONAL_FEED_PRECISION) / PRECISION;

        assertEq(totalDeposits, expectedDeposits, "Total deposits mismatch");
        assertEq(totalBorrows, expectedBorrows, "Total borrows mismatch");
        vm.stopPrank();
    }
}
