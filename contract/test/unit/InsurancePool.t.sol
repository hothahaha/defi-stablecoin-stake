// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {InsurancePool} from "../../src/InsurancePool.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract InsurancePoolTest is Test {
    InsurancePool public insurancePool;
    MockERC20 public weth;
    MockERC20 public usdc;
    address public owner;
    address public user;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");

        vm.startPrank(owner);
        insurancePool = new InsurancePool();
        weth = new MockERC20("Wrapped ETH", "WETH");
        usdc = new MockERC20("USD Coin", "USDC");
        vm.stopPrank();
    }

    function testPayPremium() public {
        uint256 amount = 1 ether;
        vm.startPrank(user);

        weth.mint(amount);
        weth.approve(address(insurancePool), amount);

        vm.expectEmit(true, true, false, true);
        emit InsurancePool.PremiumPaid(address(weth), user, amount);

        insurancePool.payPremium(address(weth), amount);

        assertEq(insurancePool.getBalance(address(weth)), amount);
        assertEq(weth.balanceOf(address(insurancePool)), amount);

        vm.stopPrank();
    }

    function testCannotPayZeroPremium() public {
        vm.startPrank(user);

        vm.expectRevert(InsurancePool.InsurancePool__InvalidAmount.selector);
        insurancePool.payPremium(address(weth), 0);

        vm.stopPrank();
    }

    function testClaim() public {
        uint256 premiumAmount = 1 ether;
        uint256 claimAmount = 0.5 ether;

        // 先支付保险费
        vm.startPrank(user);
        weth.mint(premiumAmount);
        weth.approve(address(insurancePool), premiumAmount);
        insurancePool.payPremium(address(weth), premiumAmount);
        vm.stopPrank();

        // 然后申请赔付
        vm.startPrank(user);
        vm.expectEmit(true, true, false, true);
        emit InsurancePool.ClaimPaid(address(weth), user, claimAmount);

        insurancePool.claim(address(weth), claimAmount);

        assertEq(insurancePool.getBalance(address(weth)), premiumAmount - claimAmount);
        assertEq(weth.balanceOf(user), claimAmount);

        vm.stopPrank();
    }

    function testCannotClaimZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert(InsurancePool.InsurancePool__InvalidAmount.selector);
        insurancePool.claim(address(weth), 0);

        vm.stopPrank();
    }

    function testCannotClaimMoreThanBalance() public {
        uint256 premiumAmount = 1 ether;
        uint256 claimAmount = 2 ether;

        // Pay premium
        vm.startPrank(user);
        weth.mint(premiumAmount);
        weth.approve(address(insurancePool), premiumAmount);
        insurancePool.payPremium(address(weth), premiumAmount);

        vm.expectRevert(InsurancePool.InsurancePool__InsufficientBalance.selector);
        insurancePool.claim(address(weth), claimAmount);

        vm.stopPrank();
    }

    function testCannotExceedMaxCoverage() public {
        uint256 premiumAmount = 1 ether;
        uint256 claimAmount = 0.9 ether; // 90% > MAX_COVERAGE_RATIO (80%)

        // Pay premium
        vm.startPrank(user);
        weth.mint(premiumAmount);
        weth.approve(address(insurancePool), premiumAmount);
        insurancePool.payPremium(address(weth), premiumAmount);

        vm.expectRevert(InsurancePool.InsurancePool__ExceedsMaxCoverage.selector);
        insurancePool.claim(address(weth), claimAmount);

        vm.stopPrank();
    }

    function testGetBalance() public {
        uint256 amount = 1 ether;

        vm.startPrank(user);
        weth.mint(amount);
        weth.approve(address(insurancePool), amount);
        insurancePool.payPremium(address(weth), amount);

        assertEq(insurancePool.getBalance(address(weth)), amount);
        assertEq(insurancePool.getBalance(address(usdc)), 0);

        vm.stopPrank();
    }

    function testMultipleClaimsAndPremiums() public {
        uint256 initialPremium = 1 ether;
        uint256 additionalPremium = 0.5 ether;
        uint256 firstClaim = 0.3 ether;
        uint256 secondClaim = 0.4 ether;

        vm.startPrank(user);

        // 初始化保险费
        weth.mint(initialPremium + additionalPremium);
        weth.approve(address(insurancePool), initialPremium + additionalPremium);
        insurancePool.payPremium(address(weth), initialPremium);

        // 第一次赔付
        insurancePool.claim(address(weth), firstClaim);

        // 额外支付保险费
        insurancePool.payPremium(address(weth), additionalPremium);

        // 第二次赔付
        insurancePool.claim(address(weth), secondClaim);

        uint256 expectedBalance = initialPremium + additionalPremium - firstClaim - secondClaim;
        assertEq(insurancePool.getBalance(address(weth)), expectedBalance);

        vm.stopPrank();
    }
}
