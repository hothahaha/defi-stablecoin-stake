// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployScript} from "../../script/Deploy.s.sol";
import {LendingPool} from "../../src/LendingPool.sol";
import {InsurancePool} from "../../src/InsurancePool.sol";
import {AssetManager} from "../../src/AssetManager.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract LendingPoolTest is Test {
    DeployScript deployer;
    LendingPool pool;
    InsurancePool insurancePool;
    AssetManager assetManager;
    MockERC20 rewardToken;
    MockERC20 weth;
    MockERC20 usdc;
    address ethUsdPriceFeed;
    address usdcUsdPriceFeed;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant INITIAL_DEPOSIT = 10 ether;
    uint256 public constant REWARD_PER_BLOCK = 1e18;
    int256 public constant ETH_PRICE = 2000e8;
    int256 public constant USDC_PRICE = 1e8;

    function setUp() public {
        // 部署mock tokens
        rewardToken = new MockERC20("Reward Token", "RWD");
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

        // 部署 lending pool
        pool = new LendingPool(
            address(insurancePool),
            address(rewardToken),
            REWARD_PER_BLOCK,
            address(assetManager),
            tokens,
            priceFeeds
        );

        for (uint i = 0; i < tokens.length; i++) {
            AssetManager.AssetConfig memory assetConfig = AssetManager.AssetConfig({
                isSupported: true,
                collateralFactor: 75e16, // 75%
                borrowFactor: 80e16, // 80%
                liquidationFactor: 5e16 // 5%
            });
            assetManager.addAsset(tokens[i], assetConfig);
        }

        // 借贷池中金额初始化
        weth.mint(INITIAL_DEPOSIT);
        weth.transfer(address(pool), INITIAL_DEPOSIT);
        usdc.mint(2000e18);
        usdc.transfer(address(pool), 2000e18);

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
        assertEq(address(pool.rewardToken()), address(rewardToken));
        assertEq(address(pool.insurancePool()), address(insurancePool));
        assertEq(address(pool.assetManager()), address(assetManager));
    }

    function testDeposit() public {
        vm.startPrank(USER);
        uint256 depositAmount = 1 ether;

        pool.deposit(address(weth), depositAmount);

        (uint128 userDeposit, , , ) = pool.userInfo(address(weth), USER);
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

    function testTimeWeightedDeposit() public {
        vm.startPrank(USER);
        uint256 initialDeposit = 1 ether;

        // 第一次存款
        pool.deposit(address(weth), initialDeposit);

        // 等待一段时间
        vm.warp(block.timestamp + 1 days);

        // 第二次存款
        pool.deposit(address(weth), initialDeposit);

        (uint128 userDeposit, , uint64 lastUpdateTime, ) = pool.userInfo(address(weth), USER);

        // 验证存款金额大于简单的算术和，因为包含了时间权重
        assertGt(userDeposit, initialDeposit * 2);
        assertEq(lastUpdateTime, block.timestamp);
        vm.stopPrank();
    }

    function testMultipleDepositsAndWithdraws() public {
        vm.startPrank(USER);

        // 多次存款
        pool.deposit(address(weth), 1 ether);
        pool.deposit(address(weth), 0.5 ether);
        pool.deposit(address(weth), 0.3 ether);

        // 记录总存款金额
        (uint128 totalDeposit, , , ) = pool.userInfo(address(weth), USER);

        // 部分提款
        pool.withdraw(address(weth), 0.8 ether);

        // 验证剩余金额
        (uint128 remainingDeposit, , , ) = pool.userInfo(address(weth), USER);
        assertEq(remainingDeposit, totalDeposit - 0.8 ether);

        vm.stopPrank();
    }

    function testDepositWithZeroTotalDeposits() public {
        vm.startPrank(USER);

        // 确保总存款为0
        (uint256 totalDeposits, , , , ) = pool.assetInfo(address(weth));
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

        (, uint128 userBorrow, , ) = pool.userInfo(address(usdc), USER);
        assertEq(userBorrow, borrowAmount);
        vm.stopPrank();
    }

    function testMaximumBorrowLimit() public {
        vm.startPrank(USER);
        pool.deposit(address(weth), 10 ether);

        // 尝试超额借款
        uint256 maxBorrow = (pool.getCollateralValue(USER) * 80) / 100; // 80% 借款上限
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

        (, uint128 userBorrow, , ) = pool.userInfo(address(usdc), USER);
        assertEq(userBorrow, 0);
        vm.stopPrank();
    }

    /////////////////
    // Liquidation //
    /////////////////
    function testLiquidation() public {
        vm.startPrank(USER);
        pool.deposit(address(weth), 1 ether);
        uint256 borrowAmount = 1200e18;
        pool.borrow(address(usdc), borrowAmount);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ETH_PRICE / 2);

        vm.startPrank(LIQUIDATOR);
        pool.liquidate(address(usdc), USER, 500e18);
        vm.stopPrank();

        (, uint128 userBorrow, , ) = pool.userInfo(address(usdc), USER);
        assertLt(userBorrow, borrowAmount);
    }

    function testComplexLiquidationScenario() public {
        // 设置初始状态
        vm.startPrank(USER);
        pool.deposit(address(weth), 1 ether);
        pool.borrow(address(usdc), 1200e18);
        vm.stopPrank();

        // 价格暴跌 60%
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer((ETH_PRICE * 40) / 100);

        // 准备清算
        vm.startPrank(LIQUIDATOR);
        usdc.mint(2000e18);
        usdc.approve(address(pool), 2000e18);

        // 分多次清算
        pool.liquidate(address(usdc), USER, 200e18);
        pool.liquidate(address(usdc), USER, 200e18);
        pool.liquidate(address(usdc), USER, 200e18);

        // 验证最终状态
        (, uint128 remainingBorrow, , ) = pool.userInfo(address(usdc), USER);
        assertLt(remainingBorrow, 1500e18);
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

        (uint128 userDeposit, , , ) = pool.userInfo(address(weth), USER);
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
        rewardToken.mint(1000000 ether);
        rewardToken.transfer(address(pool), 1000000 ether);
        vm.startPrank(USER);
        pool.deposit(address(weth), 1 ether);

        // 推进区块
        vm.roll(block.number + 2);

        console.log("accRewardPerShare", pool.getAccRewardPerShare(address(weth)));
        // 领取奖励
        pool.claimReward(address(weth));

        // 验证奖励
        assertGt(rewardToken.balanceOf(USER), 0);
        vm.stopPrank();
    }

    function testRewardDistribution() public {
        rewardToken.mint(1000000 ether);
        rewardToken.transfer(address(pool), 1000000 ether);
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
            assertGt(rewardToken.balanceOf(users[i]), 0);
        }
    }

    function testRewardAccrualWithTimeWeight() public {
        rewardToken.mint(1000000 ether);
        rewardToken.transfer(address(pool), 1000000 ether);

        vm.startPrank(USER);

        // 第一次存款
        pool.deposit(address(weth), 1 ether);
        uint256 initialReward = rewardToken.balanceOf(USER);

        // 等待一段时间并推进区块
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 100);

        // 再次存款触发奖励计算
        pool.deposit(address(weth), 0.5 ether);
        uint256 firstReward = rewardToken.balanceOf(USER) - initialReward;

        // 再等待并领取奖励
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 100);
        pool.claimReward(address(weth));

        uint256 secondReward = rewardToken.balanceOf(USER) - firstReward - initialReward;

        // 验证第二次奖励大于第一次（因为存款金额更多）
        assertGt(secondReward, firstReward);
        vm.stopPrank();
    }

    function testRewardCalculationPrecision() public {
        rewardToken.mint(1000000 ether);
        rewardToken.transfer(address(pool), 1000000 ether);

        vm.startPrank(USER);

        // 存入一个很小的金额
        uint256 smallDeposit = 1 wei;
        pool.deposit(address(weth), smallDeposit);

        // 推进大量区块
        vm.roll(block.number + 1000000);

        // 领取奖励
        pool.claimReward(address(weth));

        // 验证即使是小额存款也能获得奖励
        assertGt(rewardToken.balanceOf(USER), 0);

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
        assertEq(collateralValue, (depositAmount * uint256(ETH_PRICE) * 3) / 4);
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
        (uint128 user1Deposit, uint128 user1Borrow, , ) = pool.userInfo(address(weth), user1);
        (uint128 user2Deposit, uint128 user2Borrow, , ) = pool.userInfo(address(usdc), user2);

        assertEq(user1Deposit, 1 ether);
        assertEq(user2Deposit, 2000e18);
        assertEq(user1Borrow, 0);
        assertEq(user2Borrow, 0);
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
        (uint128 userDeposit, , , ) = pool.userInfo(address(weth), USER);
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
}
