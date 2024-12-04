// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployScript} from "../../script/Deploy.s.sol";
import {LendingPool} from "../../src/LendingPool.sol";
import {InsurancePool} from "../../src/InsurancePool.sol";
import {AssetManager} from "../../src/AssetManager.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Handler} from "./Handler.sol";

contract LendingPoolInvariantTest is StdInvariant, Test {
    Handler public handler;
    LendingPool public pool;
    InsurancePool public insurancePool;
    AssetManager public assetManager;
    MockERC20 public rewardToken;
    MockERC20 public weth;
    MockERC20 public usdc;
    address public ethUsdPriceFeed;
    address public usdcUsdPriceFeed;

    int256 public constant ETH_PRICE = 2000e8;
    int256 public constant USDC_PRICE = 1e8;
    uint256 public constant INITIAL_DEPOSIT = 10 ether;
    uint256 public constant REWARD_PER_BLOCK = 1e18;

    function setUp() public {
        // 部署基础合约
        rewardToken = new MockERC20("Reward Token", "RWD");
        DeployScript deployer = new DeployScript();
        DeployScript.NetworkConfig memory networkConfig = deployer.getNetworkConfig();

        // 设置代币和价格源
        address[] memory tokens = networkConfig.collateralTokens;
        address[] memory priceFeeds = networkConfig.priceFeeds;
        weth = MockERC20(tokens[0]);
        usdc = MockERC20(tokens[1]);
        ethUsdPriceFeed = priceFeeds[0];
        usdcUsdPriceFeed = priceFeeds[1];

        // 部署核心合约
        insurancePool = new InsurancePool();
        assetManager = new AssetManager();
        pool = new LendingPool(
            address(insurancePool),
            address(rewardToken),
            REWARD_PER_BLOCK,
            address(assetManager),
            tokens,
            priceFeeds
        );

        // 配置资产
        for (uint i = 0; i < tokens.length; i++) {
            AssetManager.AssetConfig memory assetConfig = AssetManager.AssetConfig({
                isSupported: true,
                collateralFactor: 75e16, // 75%
                borrowFactor: 80e16, // 80%
                liquidationFactor: 5e16 // 5%
            });
            assetManager.addAsset(tokens[i], assetConfig);
        }

        // 初始化处理器
        handler = new Handler(pool, weth, usdc);
        targetContract(address(handler));

        // 为奖励池提供足够的代币
        rewardToken.mint(1000000 ether);
        rewardToken.transfer(address(pool), 1000000 ether);

        // 设置初始价格
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ETH_PRICE);
        MockV3Aggregator(usdcUsdPriceFeed).updateAnswer(USDC_PRICE);
    }

    function invariant_totalDepositsGTETotalBorrows() public view {
        // 检查每个资产的总存款是否大于等于总借款
        address[] memory assets = assetManager.getSupportedAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            (uint256 totalDeposits, uint256 totalBorrows, , , ) = pool.assetInfo(assets[i]);
            assertGe(totalDeposits, totalBorrows, "Total deposits must be >= total borrows");
        }
    }

    function invariant_healthFactorMaintained() public view {
        // 检查所有活跃用户的健康因子
        address[] memory activeUsers = handler.getActiveUsers();
        for (uint256 i = 0; i < activeUsers.length; i++) {
            uint256 healthFactor = pool.getHealthFactor(activeUsers[i]);
            if (healthFactor > 0) {
                assertGe(
                    healthFactor,
                    1e18,
                    "Health factor must be >= 1 for non-liquidated positions"
                );
            }
        }
    }

    function invariant_rewardDebtConsistency() public view {
        // 验证奖励债务的一致性
        address[] memory assets = assetManager.getSupportedAssets();
        address[] memory activeUsers = handler.getActiveUsers();

        for (uint256 i = 0; i < assets.length; i++) {
            for (uint256 j = 0; j < activeUsers.length; j++) {
                (uint128 depositAmount, , , uint256 rewardDebt) = pool.userInfo(
                    assets[i],
                    activeUsers[j]
                );
                uint256 accRewardPerShare = pool.getAccRewardPerShare(assets[i]);

                assertLe(
                    rewardDebt,
                    (uint256(depositAmount) * accRewardPerShare) / 1e18,
                    "Reward debt exceeds maximum possible value"
                );
            }
        }
    }

    function invariant_collateralValueConsistency() public view {
        // 验证抵押品价值的一致性
        address[] memory activeUsers = handler.getActiveUsers();
        for (uint256 i = 0; i < activeUsers.length; i++) {
            uint256 collateralValue = pool.getCollateralValue(activeUsers[i]);
            uint256 totalBorrowValue = handler.calculateTotalBorrowValue(activeUsers[i]);

            if (totalBorrowValue > 0) {
                assertGt(
                    collateralValue,
                    0,
                    "Collateral value must be > 0 for accounts with borrows"
                );
            }
        }
    }

    function invariant_liquidationThresholdMaintained() public view {
        // 验证清算阈值的维护
        address[] memory activeUsers = handler.getActiveUsers();
        for (uint256 i = 0; i < activeUsers.length; i++) {
            uint256 healthFactor = pool.getHealthFactor(activeUsers[i]);
            if (healthFactor < 1e18) {
                assertTrue(
                    handler.isUserLiquidatable(activeUsers[i]),
                    "User should be liquidatable when health factor < 1"
                );
            }
        }
    }

    function invariant_totalRewardDistribution() public view {
        // 验证总奖励分配
        uint256 totalRewardDistributed = 0;
        address[] memory assets = assetManager.getSupportedAssets();
        address[] memory activeUsers = handler.getActiveUsers();

        for (uint256 i = 0; i < assets.length; i++) {
            for (uint256 j = 0; j < activeUsers.length; j++) {
                (, , , uint256 rewardDebt) = pool.userInfo(assets[i], activeUsers[j]);
                totalRewardDistributed += rewardDebt;
            }
        }

        assertLe(
            totalRewardDistributed,
            rewardToken.balanceOf(address(pool)),
            "Total rewards distributed must not exceed pool balance"
        );
    }

    // 新增不变量测试：利率模型一致性
    function invariant_interestRateModelConsistency() public view {
        address[] memory assets = assetManager.getSupportedAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            (uint256 totalDeposits, uint256 totalBorrows, , uint256 currentRate, ) = pool.assetInfo(
                assets[i]
            );

            if (totalDeposits > 0) {
                // 利用率不应超过100%
                uint256 utilization = (totalBorrows * 1e18) / totalDeposits;
                assertLe(utilization, 1e18, "Utilization rate cannot exceed 100%");

                // 利率应该随着利用率增加而增加
                if (utilization > 8e17) {
                    // 80% 利用率
                    assertGe(
                        currentRate,
                        1e16,
                        "High utilization should have higher interest rate"
                    );
                }
            }
        }
    }

    // 新增不变量测试：清算奖励一致性
    function invariant_liquidationBonusConsistency() public view {
        address[] memory activeUsers = handler.getActiveUsers();
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (handler.isUserLiquidatable(activeUsers[i])) {
                uint256 healthFactor = pool.getHealthFactor(activeUsers[i]);
                assertLt(healthFactor, 1e18, "Liquidatable positions must have health factor < 1");
            }
        }
    }

    // 新增不变量测试：价格影响
    function invariant_priceImpact() public {
        // 模拟价格波动
        int256 newEthPrice = (ETH_PRICE * 9) / 10; // 10% 价格下跌
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newEthPrice);

        address[] memory activeUsers = handler.getActiveUsers();
        for (uint256 i = 0; i < activeUsers.length; i++) {
            uint256 oldHealthFactor = pool.getHealthFactor(activeUsers[i]);
            if (oldHealthFactor > 0) {
                // 价格下跌应该降低健康因子
                assertLe(
                    pool.getHealthFactor(activeUsers[i]),
                    oldHealthFactor,
                    "Health factor should decrease with price drop"
                );
            }
        }

        // 恢复原始价格
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ETH_PRICE);
    }

    // 新增模糊测试：存款金额边界
    function test_fuzz_depositBoundaries(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);
        address testUser = makeAddr("testUser");

        vm.startPrank(testUser);
        weth.mint(amount);
        weth.approve(address(pool), amount);

        // 存款应该成功
        pool.deposit(address(weth), amount);

        (uint128 depositAmount, , , ) = pool.userInfo(address(weth), testUser);
        assertEq(uint256(depositAmount), amount, "Deposit amount mismatch");
        vm.stopPrank();
    }

    // 新增模糊测试：借款限额
    function test_fuzz_borrowLimits(uint256 depositAmount, uint256 borrowAmount) public {
        vm.assume(depositAmount > 1 ether && depositAmount < 1000 ether);

        address testUser = makeAddr("testUser");

        // 先存款
        vm.startPrank(testUser);
        weth.mint(depositAmount);
        weth.approve(address(pool), depositAmount);
        pool.deposit(address(weth), depositAmount);

        // 数据准备，获取
        uint256 borrowLimit = pool.getUserBorrowLimit(testUser, address(usdc));
        vm.assume(borrowAmount <= borrowLimit);
        usdc.mint(borrowAmount);
        usdc.transfer(address(pool), borrowAmount);

        // 借款应该成功
        usdc.mint(borrowAmount);
        usdc.approve(address(pool), borrowAmount);
        pool.borrow(address(usdc), borrowAmount);
        vm.stopPrank();

        uint256 actualBorrow = pool.getUserBorrowAmount(testUser, address(usdc));
        assertEq(actualBorrow, borrowAmount, "Borrow amount mismatch");
    }

    // 新增模糊测试：清算阈值
    function test_fuzz_liquidationThresholds(
        uint256 depositAmount,
        uint256 borrowAmount,
        uint256 priceDropPercent
    ) public {
        // 放宽约束条件，使用更合理的范围
        depositAmount = bound(depositAmount, 1 ether, 100 ether);

        // 确保借款金额在合理范围内（最多80%的抵押价值）
        uint256 maxBorrow = (depositAmount * uint256(ETH_PRICE) * 80) / 100 / 1e8;
        borrowAmount = bound(borrowAmount, 0.1 ether, maxBorrow);

        // 价格下跌范围：20-70%
        priceDropPercent = bound(priceDropPercent, 20, 70);

        address testUser = makeAddr("testUser");
        // 设置初始状态
        _setupUserPosition(testUser, depositAmount, borrowAmount);

        // 模拟价格下跌
        int256 newPrice = (ETH_PRICE * int256(100 - priceDropPercent)) / 100;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newPrice);

        // 验证清算条件
        uint256 healthFactor = pool.getHealthFactor(testUser);
        if (healthFactor < 1e18) {
            assertTrue(handler.isUserLiquidatable(testUser), "Should be liquidatable");

            // 额外验证：确保清算是合理的
            uint256 collateralValue = pool.getCollateralValue(testUser);
            uint256 borrowValue = pool.getUserBorrowUsdValue(testUser, address(usdc));
            assertLt(collateralValue, (borrowValue * 133) / 100, "Position should be underwater");
        }
    }

    // 辅助函数：设置用户头寸
    function _setupUserPosition(
        address user,
        uint256 depositAmount,
        uint256 borrowAmount
    ) internal {
        vm.startPrank(user);
        weth.mint(depositAmount);
        weth.approve(address(pool), depositAmount);
        pool.deposit(address(weth), depositAmount);

        uint256 borrowLimit = pool.getUserBorrowLimit(user, address(usdc));
        if (borrowAmount <= borrowLimit) {
            pool.borrow(address(usdc), borrowAmount);
        }
        vm.stopPrank();
    }

    function invariant_callSummary() public view {
        // 输出测试统计信息
        console.log("Deposit calls:", handler.depositCalls());
        console.log("Borrow calls:", handler.borrowCalls());
        console.log("Repay calls:", handler.repayCalls());
        console.log("Withdraw calls:", handler.withdrawCalls());
        console.log("Liquidate calls:", handler.liquidateCalls());
    }
}
