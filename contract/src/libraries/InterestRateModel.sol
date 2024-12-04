// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title 利率模型库
/// @notice 计算借贷利率
/// @dev 实现了基于资金利用率的动态利率计算
library InterestRateModel {
    // Constants
    uint256 private constant PRECISION = 1e18; // 精度
    uint256 private constant BASE_RATE = 2e16; // 基础利率 (2%)
    uint256 private constant OPTIMAL_RATE = 8e16; // 最优利率 (8%)
    uint256 private constant EXCESS_RATE = 1e18; // 超额利率 (100%)
    uint256 private constant OPTIMAL_UTILIZATION = 8e17; // 最优利用率 (80%)

    /// @notice 计算借贷利率
    /// @param totalBorrows 总借款金额
    /// @param totalDeposits 总存款金额
    /// @dev 类似Compound和Aave的利率模型，能够根据市场供需自动调节利率
    /// @dev 在正常利用率范围内(0-80%)提供平稳的利率增长
    /// @dev 当利用率超过80%时快速提高利率，以抑制过度借贷
    /// @return 年化利率 (以 1e18 为基数)
    function calculateInterestRate(
        uint256 totalBorrows,
        uint256 totalDeposits
    ) internal pure returns (uint256) {
        if (totalDeposits == 0) return BASE_RATE;

        // 计算资金利用率 borrows / deposits
        uint256 utilization = (totalBorrows * PRECISION) / totalDeposits;

        if (utilization <= OPTIMAL_UTILIZATION) {
            // 线性增长：从基础利率到最优利率
            return BASE_RATE + ((OPTIMAL_RATE - BASE_RATE) * utilization) / OPTIMAL_UTILIZATION;
        } else {
            // 指数增长：超过最优利用率后快速增长
            // 计算超额利用率
            uint256 excessUtilization = utilization - OPTIMAL_UTILIZATION;
            // 计算斜率
            uint256 slope = ((EXCESS_RATE - OPTIMAL_RATE) * PRECISION) /
                (PRECISION - OPTIMAL_UTILIZATION);
            return OPTIMAL_RATE + (slope * excessUtilization) / PRECISION;
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
}
