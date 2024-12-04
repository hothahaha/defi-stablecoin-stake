// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title 保险池合约
/// @notice 管理清算保险金的收取和赔付
/// @dev 实现了保费收取和赔付功能
contract InsurancePool is Ownable, ReentrancyGuard {
    // Constants
    uint256 public constant PREMIUM_RATE = 1e15; // 保费费率 (0.1%)
    uint256 public constant MAX_COVERAGE_RATIO = 8e17; // 最大赔付率 (80%)

    // State variables
    mapping(address => uint256) public assetBalance; // 每个资产的保险金余额

    // Events
    event PremiumPaid(address indexed asset, address indexed user, uint256 amount);
    event ClaimPaid(address indexed asset, address indexed user, uint256 amount);

    // Errors
    error InsurancePool__InsufficientBalance();
    error InsurancePool__TransferFailed();
    error InsurancePool__InvalidAmount();
    error InsurancePool__ExceedsMaxCoverage();

    /// @notice 构造函数
    /// @dev 初始化所有者
    constructor() Ownable(msg.sender) {}

    /// @notice 支付保费
    /// @param asset 资产地址
    /// @param amount 保费金额
    function payPremium(address asset, uint256 amount) external nonReentrant {
        if (amount == 0) revert InsurancePool__InvalidAmount();

        assetBalance[asset] += amount;
        SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), amount);
        emit PremiumPaid(asset, msg.sender, amount);
    }

    /// @notice 申请赔付
    /// @param asset 资产地址
    /// @param amount 赔付金额
    function claim(address asset, uint256 amount) external nonReentrant {
        if (amount == 0) revert InsurancePool__InvalidAmount();
        if (amount > assetBalance[asset]) revert InsurancePool__InsufficientBalance();

        uint256 maxClaim = (assetBalance[asset] * MAX_COVERAGE_RATIO) / 1e18;
        if (amount > maxClaim) revert InsurancePool__ExceedsMaxCoverage();

        assetBalance[asset] -= amount;
        SafeERC20.safeTransfer(IERC20(asset), msg.sender, amount);

        emit ClaimPaid(asset, msg.sender, amount);
    }

    /// @notice 获取资产余额
    /// @param asset 资产地址
    /// @return 保险池中该资产的余额
    function getBalance(address asset) external view returns (uint256) {
        return assetBalance[asset];
    }
}
