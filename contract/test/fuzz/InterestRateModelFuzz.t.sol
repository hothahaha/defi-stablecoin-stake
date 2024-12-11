// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {InterestRateModel} from "../../src/libraries/InterestRateModel.sol";

contract InterestRateModelFuzzTest is Test {
    using InterestRateModel for uint256;

    function testFuzz_InterestRateCalculation(uint256 borrows, uint256 deposits) public pure {
        // Bound inputs to reasonable ranges
        deposits = bound(deposits, 1 ether, type(uint128).max);
        borrows = bound(borrows, 0, deposits);

        uint256 rate = InterestRateModel.calculateInterestRate(borrows, deposits);

        // Verify rate is within expected bounds
        assertTrue(rate >= 2e16); // >= 2%
        assertTrue(rate <= 1e18); // <= 100%

        // Verify rate increases with utilization
        uint256 utilization = InterestRateModel.calculateUtilization(borrows, deposits);
        if (utilization > 8e17) {
            // > 80%
            assertTrue(rate > 8e16); // > 8%
        }
    }

    function testFuzz_UtilizationCalculation(uint256 borrows, uint256 deposits) public pure {
        // Bound inputs
        deposits = bound(deposits, 1 ether, type(uint128).max);
        borrows = bound(borrows, 0, deposits);

        uint256 utilization = InterestRateModel.calculateUtilization(borrows, deposits);

        // Verify utilization is within expected bounds
        assertTrue(utilization <= 1e18); // <= 100%

        // Verify utilization calculation
        if (deposits > 0) {
            assertEq(utilization, (borrows * 1e18) / deposits);
        }
    }
}
