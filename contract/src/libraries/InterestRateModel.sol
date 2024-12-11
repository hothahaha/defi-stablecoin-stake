// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title 利率模型库
/// @notice 计算借贷利率
/// @dev 实现了基于资金利用率的动态利率计算
library InterestRateModel {
    // Constants
    uint256 private constant PRECISION = 1e18;
    uint256 private constant BASE_RATE = 2e16; // 基础利率 2%
    uint256 private constant OPTIMAL_RATE = 8e16; // 最优利率 8%
    uint256 private constant EXCESS_RATE = 1e18; // 超额利率 100%
    uint256 private constant OPTIMAL_UTILIZATION = 8e17; // 最优利用率 80%
    uint256 private constant SECONDS_PER_YEAR = 31536000; // 每年秒数

    // 预计算常量以减少运行时计算
    uint256 private constant RATE_SPREAD = OPTIMAL_RATE - BASE_RATE; // 利率差值
    // 超额利率差值
    uint256 private constant EXCESS_SPREAD = EXCESS_RATE - OPTIMAL_RATE;
    // 利用率比例
    uint256 private constant UTILIZATION_SCALE = PRECISION / OPTIMAL_UTILIZATION;
    // 最大安全存款金额
    uint256 private constant MAX_SAFE_DEPOSIT = type(uint256).max / PRECISION;

    // Errors
    error InterestRateModel__DepositsTooLarge();
    error InterestRateModel__BorrowsExceedDeposits();

    /// @notice 计算存款利率
    /// @param totalBorrows 总借款金额
    /// @param totalDeposits 总存款金额
    /// @param reserveFactor 储备金率
    /// @return 存款年化利率 (以 1e18 为基数)
    function calculateDepositRate(
        uint256 totalBorrows,
        uint256 totalDeposits,
        uint256 reserveFactor
    ) internal pure returns (uint256) {
        // 获取借款利率
        uint256 borrowRate = calculateInterestRate(totalBorrows, totalDeposits);

        // 存款利率 = 借款利率 * 利用率 * (1 - 储备金率)
        uint256 utilization = calculateUtilization(totalBorrows, totalDeposits);
        return (borrowRate * utilization * (PRECISION - reserveFactor)) / (PRECISION * PRECISION);
    }

    /// @notice 计算借贷利率
    /// @param totalBorrows 总借款金额
    /// @param totalDeposits 总存款金额
    /// @return 年化利率 (以 1e18 为基数)
    function calculateInterestRate(
        uint256 totalBorrows,
        uint256 totalDeposits
    ) internal pure returns (uint256) {
        // 早期返回检查
        if (totalDeposits == 0 || totalBorrows == 0) return BASE_RATE;

        // 安全性检查
        if (totalDeposits > MAX_SAFE_DEPOSIT) revert InterestRateModel__DepositsTooLarge();
        if (totalBorrows > totalDeposits) revert InterestRateModel__BorrowsExceedDeposits();

        unchecked {
            // 计算利用率
            uint256 utilization = (totalBorrows * PRECISION) / totalDeposits;

            // 优化分支逻辑
            if (utilization <= OPTIMAL_UTILIZATION) {
                return _calculateNormalRate(utilization);
            }
            return _calculateExcessRate(utilization);
        }
    }

    /// @notice 计算资金利用率
    /// @param totalBorrows 总借款金额
    /// @param totalDeposits 总存款金额
    /// @return 资金利用率 (以 1e18 为基数)
    function calculateUtilization(
        uint256 totalBorrows,
        uint256 totalDeposits
    ) internal pure returns (uint256) {
        if (totalDeposits == 0) return 0;
        return (totalBorrows * PRECISION) / totalDeposits;
    }

    /// @notice 计算累积利息
    /// @param principal 本金
    /// @param rate 年化利率
    /// @param timeElapsed 经过时间(秒)
    /// @return 累积的利息
    function calculateInterest(
        uint256 principal,
        uint256 rate,
        uint256 timeElapsed
    ) internal pure returns (uint256) {
        return (principal * rate * timeElapsed) / (PRECISION * SECONDS_PER_YEAR);
    }

    /// @dev 计算正常利率区间的利率
    function _calculateNormalRate(uint256 utilization) private pure returns (uint256) {
        return BASE_RATE + ((RATE_SPREAD * utilization) / OPTIMAL_UTILIZATION);
    }

    /// @dev 计算超额利率区间的利率
    function _calculateExcessRate(uint256 utilization) private pure returns (uint256) {
        // 1. 计算超额利用率（以20%为基数）
        // 例如：85%利用率时，超额部分为 5%
        uint256 excessUtilization = utilization - OPTIMAL_UTILIZATION; // 0.05e18

        // 2. 计算在超额区间的位置（0-20%映射到0-100%）
        // 超额区间总长度为 20%（100% - 80%）
        uint256 remainingUtilization = PRECISION - OPTIMAL_UTILIZATION; // 0.2e18

        // 3. 计算超额利率
        // EXCESS_SPREAD = 92%（100% - 8%）
        // 在85%利用率时：(0.05e18 * 0.92e18) / 0.2e18 = 0.23e18
        // 最终利率：8% + 22% = 30%
        uint256 additionalRate = (excessUtilization * EXCESS_SPREAD) / remainingUtilization;

        return OPTIMAL_RATE + additionalRate;
    }
}
