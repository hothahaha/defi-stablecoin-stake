// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {LendingPool} from "../../src/LendingPool.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {AssetManager} from "../../src/AssetManager.sol";

contract Handler is Test {
    LendingPool public pool;
    MockERC20 public weth;
    MockERC20 public usdc;

    // 追踪活跃用户
    address[] public activeUsers;
    mapping(address => bool) public isActiveUser;

    // 操作计数器
    uint256 public depositCalls;
    uint256 public borrowCalls;
    uint256 public repayCalls;
    uint256 public withdrawCalls;
    uint256 public liquidateCalls;

    // 常量
    uint256 public constant MAX_DEPOSIT = 1000 ether;
    uint256 private constant MIN_DEPOSIT = 0.1 ether;

    constructor(LendingPool _pool, MockERC20 _weth, MockERC20 _usdc) {
        pool = _pool;
        weth = _weth;
        usdc = _usdc;
    }

    // 模糊测试：存款操作
    function deposit(uint256 amount, address user) public {
        // 约束入参
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);
        if (user == address(0)) return;

        // 准备代币
        weth.mint(amount);
        vm.startPrank(user);
        weth.approve(address(pool), amount);

        try pool.deposit(address(weth), amount) {
            depositCalls++;
            if (!isActiveUser[user]) {
                activeUsers.push(user);
                isActiveUser[user] = true;
            }
        } catch {
            // 存款失败时静默处理
        }
        vm.stopPrank();
    }

    // 模糊测试：借款操作
    function borrow(uint256 amount, address user) public {
        if (!isActiveUser[user]) return;

        // 获取用户借款限额
        uint256 borrowLimit = pool.getUserBorrowLimit(user, address(usdc));
        if (borrowLimit == 0) return;

        // 约束借款金额
        amount = bound(amount, 0, borrowLimit);
        if (amount == 0) return;

        vm.startPrank(user);
        try pool.borrow(address(usdc), amount) {
            borrowCalls++;
        } catch {
            // 借款失败时静默处理
        }
        vm.stopPrank();
    }

    // 模糊测试：还款操作
    function repay(uint256 amount, address user) public {
        if (!isActiveUser[user]) return;

        // 获取用户当前借款金额
        uint256 borrowAmount = pool.getUserBorrowAmount(user, address(usdc));
        if (borrowAmount == 0) return;

        // 约束还款金额
        amount = bound(amount, 0, borrowAmount);
        if (amount == 0) return;

        // 准备代币
        usdc.mint(amount);
        vm.startPrank(user);
        usdc.approve(address(pool), amount);

        try pool.repay(address(usdc), amount) {
            repayCalls++;
        } catch {
            // 还款失败时静默处理
        }
        vm.stopPrank();
    }

    // 模糊测试：提款操作
    function withdraw(uint256 amount, address user) public {
        if (!isActiveUser[user]) return;

        // 获取用户存款信息
        (uint128 depositAmount, , , , , ) = pool.userInfo(address(weth), user);
        if (depositAmount == 0) return;

        // 约束提款金额
        amount = bound(amount, 0, uint256(depositAmount));
        if (amount == 0) return;

        vm.startPrank(user);
        try pool.withdraw(address(weth), amount) {
            withdrawCalls++;
        } catch {
            // 提款失败时静默处理
        }
        vm.stopPrank();
    }

    // 获取活跃用户列表
    function getActiveUsers() external view returns (address[] memory) {
        return activeUsers;
    }

    // 接收函数，允许合约接收ETH
    receive() external payable {}
}
