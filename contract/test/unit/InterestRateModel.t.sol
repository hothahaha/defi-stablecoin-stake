// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {InterestRateModel} from "../../src/libraries/InterestRateModel.sol";

contract InterestRateModelTest is Test {
    // 验证精确的利率点
    struct TestPoint {
        uint256 utilization;
        uint256 expectedRate;
    }

    // 测试合约以访问库函数
    using InterestRateModel for uint256;

    // Constants for testing
    uint256 constant PRECISION = 1e18;
    uint256 constant BASE_RATE = 2e16;
    uint256 constant OPTIMAL_RATE = 8e16;
    uint256 constant EXCESS_RATE = 1e18;
    uint256 constant OPTIMAL_UTILIZATION = 8e17;

    function test_ZeroDeposits() public pure {
        uint256 rate = InterestRateModel.calculateInterestRate(0, 0);
        assertEq(rate, BASE_RATE);
    }

    function test_ZeroBorrows() public pure {
        uint256 rate = InterestRateModel.calculateInterestRate(0, 1 ether);
        assertEq(rate, BASE_RATE);
    }

    function test_RevertOnExcessiveDeposits() public {
        uint256 maxDeposit = type(uint256).max / PRECISION;
        uint256 borrows = maxDeposit / 2;

        vm.expectRevert(InterestRateModel.InterestRateModel__DepositsTooLarge.selector);
        InterestRateModel.calculateInterestRate(borrows, maxDeposit + 1);
    }

    function test_RevertOnExcessiveBorrows() public {
        uint256 deposits = 100 ether;
        uint256 borrows = 101 ether;

        vm.expectRevert(InterestRateModel.InterestRateModel__BorrowsExceedDeposits.selector);
        InterestRateModel.calculateInterestRate(borrows, deposits);
    }

    function test_OptimalUtilization() public pure {
        uint256 deposits = 100 ether;
        uint256 borrows = 80 ether; // 80% utilization
        uint256 rate = InterestRateModel.calculateInterestRate(borrows, deposits);
        assertEq(rate, OPTIMAL_RATE);
    }

    function test_RateCurveConsistency() public pure {
        uint256 deposits = 100 ether;
        uint256[] memory utilizationPoints = new uint256[](4);
        utilizationPoints[0] = 40 ether; // 40%
        utilizationPoints[1] = 60 ether; // 60%
        utilizationPoints[2] = 80 ether; // 80%
        utilizationPoints[3] = 90 ether; // 90%

        uint256 prevRate = 0;
        for (uint256 i = 0; i < utilizationPoints.length; i++) {
            uint256 rate = InterestRateModel.calculateInterestRate(utilizationPoints[i], deposits);
            assertTrue(rate >= prevRate, "Rate must increase monotonically");
            if (i == 2) {
                assertEq(rate, OPTIMAL_RATE, "80% utilization should yield optimal rate");
            }
            prevRate = rate;
        }
    }

    function test_ExcessUtilization() public pure {
        uint256 deposits = 100 ether;
        uint256 borrows = 90 ether; // 90% utilization
        uint256 rate = InterestRateModel.calculateInterestRate(borrows, deposits);
        console.log("rate", rate);
        assertTrue(rate > OPTIMAL_RATE);
        assertTrue(rate <= EXCESS_RATE);
    }

    function test_UtilizationCalculation() public pure {
        uint256 deposits = 100 ether;
        uint256 borrows = 50 ether;
        uint256 utilization = InterestRateModel.calculateUtilization(borrows, deposits);
        assertEq(utilization, 5e17); // 50%
    }

    function test_ExcessRateExactCalculation() public pure {
        uint256 deposits = 100 ether;

        TestPoint[] memory points = new TestPoint[](4);
        points[0] = TestPoint(80 ether, 8e16); // 80% -> 8%
        points[1] = TestPoint(85 ether, 31e16); // 85% -> 30%
        points[2] = TestPoint(90 ether, 54e16); // 90% -> 54%
        points[3] = TestPoint(95 ether, 77e16); // 95% -> 77%

        for (uint256 i = 0; i < points.length; i++) {
            uint256 rate = InterestRateModel.calculateInterestRate(points[i].utilization, deposits);

            assertEq(
                rate,
                points[i].expectedRate,
                string.concat(
                    "Rate mismatch at utilization: ",
                    vm.toString(points[i].utilization / 1e16),
                    "%"
                )
            );
        }
    }

    function test_ExcessRateSlope() public pure {
        uint256 deposits = 100 ether;
        uint256 prevRate;

        // 测试85%到95%之间的利率斜率
        for (uint256 util = 85; util <= 95; util += 1) {
            uint256 borrows = (deposits * util) / 100;
            uint256 rate = InterestRateModel.calculateInterestRate(borrows, deposits);

            if (util > 85) {
                uint256 rateIncrease = rate - prevRate;
                // 验证利率增长是否合理（不会突然剧烈变化）
                assertTrue(
                    rateIncrease > 0 && rateIncrease <= 1e17,
                    "Rate increase should be gradual"
                );
            }
            prevRate = rate;
        }
    }

    function test_MaximumRate() public pure {
        uint256 deposits = 100 ether;
        uint256 borrows = 99 ether; // 99% utilization

        uint256 rate = InterestRateModel.calculateInterestRate(borrows, deposits);

        // 确保利率不超过最大值
        assertTrue(rate <= EXCESS_RATE, "Rate exceeds maximum");
        // 确保接近但不等于最大利率
        assertTrue(rate >= 95e16, "Rate should be near maximum at high utilization");
    }
}
