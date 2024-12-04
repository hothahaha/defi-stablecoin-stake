// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title 时间加权收益计算库
/// @notice 计算基于存款时间的加权收益
/// @dev 实现了线性增长的时间权重计算
library TimeWeightedRewards {
    // Constants
    uint256 private constant BASE_WEIGHT = 1e18;              // 基础权重 (1.0)
    uint256 private constant MAX_WEIGHT_MULTIPLIER = 2e18;    // 最大权重倍数 (2.0)
    uint256 private constant MAX_WEIGHT_PERIOD = 365 days;    // 达到最大权重所需时间
    
    /// @notice 计算时间加权系数
    /// @param depositTime 存款时间
    /// @param currentTime 当前时间
    /// @return 时间加权系数
    function calculateTimeWeight(
        uint256 depositTime,
        uint256 currentTime
    ) internal pure returns (uint256) {
        if (currentTime <= depositTime) return BASE_WEIGHT;
        
        uint256 timeElapsed = currentTime - depositTime;
        if (timeElapsed >= MAX_WEIGHT_PERIOD) {
            return MAX_WEIGHT_MULTIPLIER;
        }
        
        // 线性增长权重
        uint256 weightIncrease = ((MAX_WEIGHT_MULTIPLIER - BASE_WEIGHT) * timeElapsed) / MAX_WEIGHT_PERIOD;
        return BASE_WEIGHT + weightIncrease;
    }
    
    /// @notice 计算加权收益
    /// @param amount 基础金额
    /// @param depositTime 存款时间
    /// @param currentTime 当前时间
    /// @return 加权后的金额
    function calculateWeightedAmount(
        uint256 amount,
        uint256 depositTime,
        uint256 currentTime
    ) internal pure returns (uint256) {
        uint256 weight = calculateTimeWeight(depositTime, currentTime);
        return (amount * weight) / BASE_WEIGHT;
    }
} 