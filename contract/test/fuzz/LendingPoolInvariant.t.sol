// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployScript} from "../../script/Deploy.s.sol";
import {LendingPool} from "../../src/LendingPool.sol";
import {InsurancePool} from "../../src/InsurancePool.sol";
import {AssetManager} from "../../src/AssetManager.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Handler} from "./Handler.sol";

contract LendingPoolInvariantTest is StdInvariant, Test {
    Handler public handler;
    LendingPool public pool;
    InsurancePool public insurancePool;
    AssetManager public assetManager;
    DecentralizedStableCoin public dsc;
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
        dsc = new DecentralizedStableCoin("Decentralized Stable Coin", "DSC");
        pool = new LendingPool(
            address(insurancePool),
            address(dsc),
            REWARD_PER_BLOCK,
            address(assetManager),
            tokens,
            priceFeeds
        );

        assetManager.setLendingPool(address(pool));
        dsc.updateMinter(address(pool), true);

        // 配置资产
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

        // 初始化处理器
        handler = new Handler(pool, weth, usdc);
        targetContract(address(handler));

        // 设置初始价格
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ETH_PRICE);
        MockV3Aggregator(usdcUsdPriceFeed).updateAnswer(USDC_PRICE);
    }

    function invariant_totalDepositsGTETotalBorrows() public view {
        // 检查每个资产的总存款是否大于等于总借款
        address[] memory assets = assetManager.getSupportedAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            (uint256 totalDeposits, uint256 totalBorrows, , , , , , , ) = pool.assetInfo(assets[i]);
            assertGe(totalDeposits, totalBorrows, "Total deposits must be >= total borrows");
        }
    }

    function invariant_rewardDebtConsistency() public view {
        // 验证奖励债务的一致性
        address[] memory assets = assetManager.getSupportedAssets();
        address[] memory activeUsers = handler.getActiveUsers();

        for (uint256 i = 0; i < assets.length; i++) {
            for (uint256 j = 0; j < activeUsers.length; j++) {
                (uint128 depositAmount, , , uint256 rewardDebt, , ) = pool.userInfo(
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
            (, uint256 totalBorrowValue) = pool.getUserTotalValueInUSD(activeUsers[i]);

            if (totalBorrowValue > 0) {
                assertGt(
                    collateralValue,
                    0,
                    "Collateral value must be > 0 for accounts with borrows"
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
                (, , , uint256 rewardDebt, , ) = pool.userInfo(assets[i], activeUsers[j]);
                totalRewardDistributed += rewardDebt;
            }
        }

        assertLe(
            totalRewardDistributed,
            dsc.balanceOf(address(pool)),
            "Total rewards distributed must not exceed pool balance"
        );
    }

    // 新增不变量测试：利率模型一致性
    function invariant_interestRateModelConsistency() public view {
        address[] memory assets = assetManager.getSupportedAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            (uint256 totalDeposits, uint256 totalBorrows, , uint256 currentRate, , , , , ) = pool
                .assetInfo(assets[i]);

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

    // 新增模糊测试：存款金额边界
    function test_fuzz_depositBoundaries(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);
        address testUser = makeAddr("testUser");

        vm.startPrank(testUser);
        weth.mint(amount);
        weth.approve(address(pool), amount);

        // 存款应该成功
        pool.deposit(address(weth), amount);

        (uint128 depositAmount, , , , , ) = pool.userInfo(address(weth), testUser);
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
        vm.assume(borrowAmount > 0 && borrowAmount <= borrowLimit);
        usdc.mint(borrowAmount);
        usdc.transfer(address(pool), borrowAmount);

        // 借款应该成功
        pool.borrow(address(usdc), borrowAmount);
        vm.stopPrank();

        uint256 actualBorrow = pool.getUserBorrowAmount(testUser, address(usdc));
        assertEq(actualBorrow, borrowAmount, "Borrow amount mismatch");
    }

    function invariant_callSummary() public view {
        // 输出测试统计信息
        console.log("Deposit calls:", handler.depositCalls());
        console.log("Borrow calls:", handler.borrowCalls());
        console.log("Repay calls:", handler.repayCalls());
        console.log("Withdraw calls:", handler.withdrawCalls());
        console.log("Liquidate calls:", handler.liquidateCalls());
    }

    // 新增状态转换模糊测试
    function test_fuzz_stateTransitions(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 borrowAmount,
        uint256 repayAmount,
        uint256 timeElapsed
    ) public {
        // 约束输入范围
        depositAmount = bound(depositAmount, 1 ether, 100 ether);
        timeElapsed = bound(timeElapsed, 1 days, 365 days);

        address testUser = makeAddr("testUser");

        // 状态1: 存款
        vm.startPrank(testUser);
        weth.mint(depositAmount);
        weth.approve(address(pool), depositAmount + 100);
        pool.deposit(address(weth), depositAmount);

        // 验证存款状态
        (uint128 depositBalance, , , , , ) = pool.userInfo(address(weth), testUser);
        assertEq(depositBalance, depositAmount);

        // 状态2: 借款
        borrowAmount = bound(
            borrowAmount,
            0.1 ether,
            pool.getUserBorrowLimit(testUser, address(weth))
        );
        pool.borrow(address(weth), borrowAmount);
        (, uint128 borrowBalance, , , , ) = pool.userInfo(address(weth), testUser);
        assertEq(borrowBalance, borrowAmount);

        // 状态3: 时间推移，利息累积
        vm.warp(block.timestamp + timeElapsed);
        pool.deposit(address(weth), 1); // 触发利息更新

        // 状态4: 部分还款
        repayAmount = bound(repayAmount, 0, borrowAmount);
        if (repayAmount > 0) {
            weth.mint(repayAmount);
            weth.approve(address(pool), repayAmount);
            pool.repay(address(weth), repayAmount);
        }

        // 状态5: 部分提款
        withdrawAmount = bound(
            withdrawAmount,
            0,
            pool.getMaxWithdrawAmount(testUser, address(weth))
        );
        if (withdrawAmount > 0) {
            pool.withdraw(address(weth), withdrawAmount);
        }

        vm.stopPrank();
    }

    // 新增利率模型模糊测试
    function test_fuzz_interestRateModel(
        uint256 depositAmount,
        uint256 borrowAmount,
        uint256 timeElapsed
    ) public {
        // 约束输入范围
        depositAmount = bound(depositAmount, 1 ether, 10 ether);
        timeElapsed = bound(timeElapsed, 1 days, 365 days);

        address testUser = makeAddr("testUser");
        vm.startPrank(testUser);
        weth.mint(depositAmount);
        weth.approve(address(pool), depositAmount);

        pool.deposit(address(weth), depositAmount);

        borrowAmount = bound(
            borrowAmount,
            0.5 ether,
            pool.getUserBorrowLimit(testUser, address(weth))
        );

        pool.borrow(address(weth), borrowAmount);

        // 记录初始利率
        (, , , uint256 initialRate, , , , , ) = pool.assetInfo(address(weth));

        // 时间推移
        vm.warp(block.timestamp + timeElapsed);
        weth.mint(depositAmount);
        weth.approve(address(pool), depositAmount);
        pool.deposit(address(weth), 1); // 触发利率更新

        // 获取更新后的利率
        (, , , uint256 newRate, , , , , ) = pool.assetInfo(address(weth));

        // 验证利率变化的合理性
        uint256 utilization = (borrowAmount * 1e18) / depositAmount;
        if (utilization > 8e17) {
            // 80% 利用率
            assertGe(newRate, initialRate, "Interest rate should increase with high utilization");
        }
        vm.stopPrank();
    }

    function test_fuzz_multipleOperations(
        uint256[5] memory depositAmounts,
        uint256[5] memory borrowAmounts,
        uint256[5] memory withdrawAmounts,
        uint256[5] memory repayAmounts,
        uint256[5] memory timeJumps
    ) public {
        usdc.mint(1000000e18);
        usdc.transfer(address(pool), 1000000e18);

        address testUser = makeAddr("testUser");
        vm.startPrank(testUser);

        // 初始化用户资金
        weth.mint(100 ether);
        usdc.mint(1000000e18);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);

        // 记录初始状态
        uint256 totalDeposits = 0;
        uint256 totalBorrows = 0;

        for (uint i = 0; i < 5; i++) {
            console.log("--------------------------------");
            // 约束输入范围
            depositAmounts[i] = bound(depositAmounts[i], 0.1 ether, 10 ether);
            timeJumps[i] = bound(timeJumps[i], 1 days, 7 days);

            // 1. 存款操作
            if (depositAmounts[i] > 0) {
                pool.deposit(address(weth), depositAmounts[i]);
                totalDeposits += depositAmounts[i];
            }

            // 2. 借款操作
            uint256 maxBorrow = pool.getUserBorrowLimit(testUser, address(usdc));
            borrowAmounts[i] = bound(borrowAmounts[i], 1, maxBorrow);

            if (borrowAmounts[i] > 0) {
                pool.borrow(address(usdc), borrowAmounts[i]);
                totalBorrows += borrowAmounts[i];
            }

            // 3. 时间推进
            vm.warp(block.timestamp + timeJumps[i]);
            vm.roll(block.number + timeJumps[i] / 12); // 假设12秒一个区块

            // 4. 还款操作
            if (totalBorrows > 0) {
                repayAmounts[i] = bound(repayAmounts[i], 0, totalBorrows);
                if (repayAmounts[i] > 0) {
                    pool.repay(address(usdc), repayAmounts[i]);
                    totalBorrows = totalBorrows > repayAmounts[i]
                        ? totalBorrows - repayAmounts[i]
                        : 0;
                }
            }

            // 5. 提款操作
            if (totalDeposits > 0) {
                uint256 maxWithdraw = pool.getMaxWithdrawAmount(testUser, address(weth));
                withdrawAmounts[i] = bound(withdrawAmounts[i], 0, maxWithdraw);

                if (withdrawAmounts[i] > 0) {
                    pool.withdraw(address(weth), withdrawAmounts[i]);
                    totalDeposits = totalDeposits > withdrawAmounts[i]
                        ? totalDeposits - withdrawAmounts[i]
                        : 0;
                }
            }

            _verifyState(testUser, totalDeposits, totalBorrows);

            // 验证不变量
            _verifyInvariants(testUser);
        }

        vm.stopPrank();
    }

    function _verifyState(
        address user,
        uint256 expectedDeposits,
        uint256 expectedBorrows
    ) internal view {
        // 验证存款
        (uint128 actualDeposits, , , , , ) = pool.userInfo(address(weth), user);
        assertEq(uint256(actualDeposits), expectedDeposits, "Deposit amount mismatch");

        // 验证借款
        (, uint128 actualBorrows, , , , ) = pool.userInfo(address(usdc), user);
        assertEq(uint256(actualBorrows), expectedBorrows, "Borrow amount mismatch");

        // 验证资产总量
        (uint256 totalPoolDeposits, , , , , , , , ) = pool.assetInfo(address(weth));
        assertGe(uint256(totalPoolDeposits), expectedDeposits, "Pool deposits inconsistent");
    }

    // 辅助函数：验证系统不变量
    function _verifyInvariants(address user) internal view {
        // 1. 借款限额检查
        (, uint256 totalBorrows) = pool.getUserTotalValueInUSD(user);
        uint256 borrowLimit = pool.getUserBorrowLimitInUSD(user);
        assertLe(totalBorrows, borrowLimit, "Borrows exceed limit");

        // 2. 存款和借款余额检查
        (uint128 deposits, uint128 borrows, , , , ) = pool.userInfo(address(weth), user);
        assertGe(deposits, 0, "Negative deposits");
        assertGe(borrows, 0, "Negative borrows");
    }
}
