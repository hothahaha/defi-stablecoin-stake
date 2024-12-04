// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {InterestRateModel} from "./libraries/InterestRateModel.sol";
import {TimeWeightedRewards} from "./libraries/TimeWeightedRewards.sol";
import {InsurancePool} from "./InsurancePool.sol";
import {API3Feed} from "./price-feeds/API3Feed.sol";
import {AssetManager} from "./AssetManager.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/// @title 借贷池合约
/// @notice 管理存款、借款和还款业务
contract LendingPool is Ownable, ReentrancyGuard, Pausable {
    // 使用 OracleLib 库处理价格源
    using OracleLib for AggregatorV3Interface;

    // Type declarations
    struct UserInfo {
        uint128 depositAmount; // 用户存款金额
        uint128 borrowAmount; // 用户借款金额
        uint64 lastUpdateTime; // 最后更新时间
        uint256 rewardDebt; // 奖励债务
    }

    struct AssetInfo {
        uint256 totalDeposits; // 总存款
        uint256 totalBorrows; // 总借款
        uint256 lastUpdateTime; // 最后更新时间
        uint256 currentRate; // 当前利率
        uint256 collateralFactor; // 抵押率
    }

    // State variables
    // Constants
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private immutable LIQUIDATION_THRESHOLD = 11e17; // 最小清算阈值 (110%)
    uint256 private immutable LIQUIDATION_BONUS = 5e16; // 清算奖励 (5%)

    // Immutable state variables
    InsurancePool public immutable insurancePool; // 保险池合约
    IERC20 public immutable rewardToken; // 奖励代币
    AssetManager public immutable assetManager; // 资产管理器

    // Mutable state variables
    mapping(address token => address priceFeed) private s_priceFeeds; // 价格预言机
    mapping(address => mapping(address => UserInfo)) public userInfo; // 用户信息
    mapping(address => AssetInfo) public assetInfo; // 资产信息
    mapping(address => uint256) public accRewardPerShare; // 每份额累计奖励
    uint256 public rewardPerBlock; // 每区块奖励
    uint256 public lastRewardBlock; // 最后奖励区块
    address[] private s_assertTokens; // 支持的资产

    // Events
    event Deposit(
        address indexed asset,
        address indexed user,
        uint256 indexed amount,
        uint256 timestamp
    );
    event Withdraw(address indexed asset, address indexed user, uint256 amount);
    event Borrow(address indexed asset, address indexed user, uint256 amount);
    event Repay(address indexed asset, address indexed user, uint256 amount);
    event Liquidate(
        address indexed asset,
        address indexed user,
        address indexed liquidator,
        uint256 amount
    );
    event AssetInfoUpdated(address indexed asset, uint256 newRate, uint256 accRewardPerShare);

    // Errors
    error LendingPool__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error LendingPool__InvalidAmount();
    error LendingPool__InsufficientCollateral();
    error LendingPool__NotLiquidatable();
    error LendingPool__WithdrawalExceedsThreshold();
    error LendingPool__AssetNotSupported();
    error LendingPool__ExceedsMaxBorrowFactor();
    error LendingPool__InvalidCollateralFactor();
    error LendingPool__ExceedsAvailableLiquidity(uint256 requested, uint256 available);
    error LendingPool__InvalidCollateralRatio(uint256 current, uint256 required);
    error LendingPool__TransferFailed();
    error LendingPool__HealthFactorOk();
    error LendingPool__HealthFactorNotImproved();
    error LendingPool__InsufficientBalance();
    error LendingPool__WithdrawExceedsThreshold();

    /// @notice 构造函数
    /// @param _insurancePool 保险池地址
    /// @param _rewardToken 奖励代币地址
    /// @param _rewardPerBlock 每区块奖励
    /// @param _assetManager 资产管理器地址
    constructor(
        address _insurancePool,
        address _rewardToken,
        uint256 _rewardPerBlock,
        address _assetManager,
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses
    ) Ownable(msg.sender) {
        insurancePool = InsurancePool(_insurancePool);
        rewardToken = IERC20(_rewardToken);
        rewardPerBlock = _rewardPerBlock;
        lastRewardBlock = block.number;
        assetManager = AssetManager(_assetManager);

        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert LendingPool__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_assertTokens.push(tokenAddresses[i]);
        }
    }

    /// @notice 暂停所有操作
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice 恢复所有操作
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice 存款前检查
    /// @param asset 资产地址
    modifier onlySupportedAsset(address asset) {
        if (!assetManager.isAssetSupported(asset)) {
            revert LendingPool__AssetNotSupported();
        }
        _;
    }

    /// @notice 存款
    /// @param asset 资产地址
    /// @param amount 存款金额
    /// @dev
    function deposit(
        address asset,
        uint256 amount
    ) external nonReentrant whenNotPaused onlySupportedAsset(asset) {
        if (amount == 0) {
            revert LendingPool__InvalidAmount();
        }

        UserInfo storage user = userInfo[asset][msg.sender];
        AssetInfo storage assetData = assetInfo[asset];
        // 计算时间加权奖励
        uint256 weightedAmount;
        if (user.depositAmount > 0 && user.lastUpdateTime > 0) {
            // 计算现有存款的时间加权金额
            uint256 existingWeightedAmount = TimeWeightedRewards.calculateWeightedAmount(
                user.depositAmount,
                user.lastUpdateTime,
                block.timestamp
            );
            // 新存款金额加上时间加权后的现有存款
            weightedAmount = amount + existingWeightedAmount;
        } else {
            weightedAmount = amount;
        }
        // 更新用户信息
        user.depositAmount = uint128(weightedAmount);
        user.lastUpdateTime = uint64(block.timestamp);
        assetData.totalDeposits += amount;
        // 执行转账
        SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), amount);
        // 更新资产信息和奖励
        updateAssetInfo(asset);
        // 更新奖励债务（代币奖励）
        uint256 pending = (weightedAmount * accRewardPerShare[asset]) / 1e18 - user.rewardDebt;
        if (pending > 0) {
            SafeERC20.safeTransfer(rewardToken, msg.sender, pending);
        }
        user.rewardDebt = (weightedAmount * accRewardPerShare[asset]) / 1e18;

        emit Deposit(asset, msg.sender, amount, block.timestamp);
    }

    /// @notice 借款
    /// @param asset 资产地址
    /// @param amount 借款金额
    /// @dev 借款前需要先存款
    function borrow(
        address asset,
        uint256 amount
    ) external nonReentrant whenNotPaused onlySupportedAsset(asset) {
        AssetManager.AssetConfig memory config = assetManager.getAssetConfig(asset);
        UserInfo storage user = userInfo[asset][msg.sender];
        // 获取用户抵押品价值（已经���USD计价）
        uint256 collateralValue = getCollateralValue(msg.sender);
        // 获取资产价格
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[asset]);
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        // 计算当前借款总价值（USD）
        uint256 currentBorrowValueUSD = (user.borrowAmount * uint256(price));
        // 计算新借款价值（USD）
        uint256 newBorrowValueUSD = (amount * uint256(price));
        // 计算借款限额（USD）
        uint256 borrowLimitUSD = (collateralValue * config.borrowFactor) / 1e18;

        // 检查总借款价值是否超过限额
        if (currentBorrowValueUSD + newBorrowValueUSD > borrowLimitUSD) {
            revert LendingPool__ExceedsMaxBorrowFactor();
        }
        // 更新用户借款金额
        user.borrowAmount = uint128(user.borrowAmount + amount);
        user.lastUpdateTime = uint64(block.timestamp);
        // 更新资产总借款金额
        AssetInfo storage assetData = assetInfo[asset];
        assetData.totalBorrows += amount;

        SafeERC20.safeTransfer(IERC20(asset), msg.sender, amount);
        // 更新资产信息和奖励
        updateAssetInfo(asset);

        emit Borrow(asset, msg.sender, amount);
    }

    /// @notice 还款
    /// @param asset 资产地址
    /// @param amount 还款金额
    function repay(address asset, uint256 amount) external nonReentrant {
        UserInfo storage user = userInfo[asset][msg.sender];
        uint256 repayAmount = amount > user.borrowAmount ? user.borrowAmount : amount;

        user.borrowAmount = uint128(user.borrowAmount - repayAmount);
        user.lastUpdateTime = uint64(block.timestamp);

        AssetInfo storage assetData = assetInfo[asset];
        assetData.totalBorrows -= repayAmount;

        SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), repayAmount);
        // 更新资产信息和奖励
        updateAssetInfo(asset);

        emit Repay(asset, msg.sender, repayAmount);
    }

    /// @notice 清算不良头寸
    /// @param asset 资产地址
    /// @param user 被清算用户地址
    /// @param repayAmount 清算金额
    function liquidate(
        address asset,
        address user,
        uint256 repayAmount
    ) external nonReentrant whenNotPaused {
        UserInfo storage borrower = userInfo[asset][user];
        uint256 startingHealthFactor = _healthFactor(user);

        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert LendingPool__HealthFactorOk();
        }

        uint256 actualRepayAmount;
        uint256 bonus;
        {
            actualRepayAmount = repayAmount > borrower.borrowAmount
                ? uint256(borrower.borrowAmount)
                : repayAmount;
            bonus = (actualRepayAmount * LIQUIDATION_BONUS) / PRECISION;
        }

        borrower.borrowAmount -= uint128(actualRepayAmount);
        borrower.lastUpdateTime = uint64(block.timestamp);

        _handleLiquidationTransfers(asset, user, msg.sender, actualRepayAmount, bonus);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert LendingPool__HealthFactorNotImproved();
        }

        emit Liquidate(asset, user, msg.sender, actualRepayAmount);
    }

    /// @notice 更新并领取奖励
    /// @param asset 资产地址
    function claimReward(address asset) external nonReentrant {
        updateAssetInfo(asset);
        UserInfo storage user = userInfo[asset][msg.sender];

        uint256 pending = (user.depositAmount * accRewardPerShare[asset]) / 1e18 - user.rewardDebt;

        if (pending > 0) {
            user.rewardDebt = (user.depositAmount * accRewardPerShare[asset]) / 1e18;
            SafeERC20.safeTransfer(rewardToken, msg.sender, pending);
        }
    }

    /// @notice 更新资产信息和奖励
    /// @param asset 资产地址
    /// @dev 更新资产信息和奖励，获取区块奖励，计算存款的奖励份额
    function updateAssetInfo(address asset) internal {
        AssetInfo storage assetData = assetInfo[asset];
        uint256 _lastRewardBlock = lastRewardBlock;

        if (block.number <= _lastRewardBlock) return;

        uint256 reward;
        unchecked {
            uint256 multiplier = block.number - _lastRewardBlock;
            reward = multiplier * rewardPerBlock;
        }

        if (assetData.totalDeposits > 0) {
            accRewardPerShare[asset] += (reward * 1e18) / assetData.totalDeposits;
        }

        // 更新资产利率
        assetData.currentRate = InterestRateModel.calculateInterestRate(
            assetData.totalBorrows,
            assetData.totalDeposits
        );

        lastRewardBlock = block.number;
        assetData.lastUpdateTime = block.timestamp;

        emit AssetInfoUpdated(asset, assetData.currentRate, accRewardPerShare[asset]);
    }

    /// @notice 提取存款
    /// @param asset 资产地址
    /// @param amount 提取金额
    function withdraw(address asset, uint256 amount) external nonReentrant {
        UserInfo storage user = userInfo[asset][msg.sender];
        if (user.depositAmount < amount) {
            revert LendingPool__InsufficientBalance();
        }

        // 检查提取后的抵押率
        uint256 newCollateralValue = getCollateralValue(msg.sender) - amount;
        if (
            user.borrowAmount > 0 &&
            newCollateralValue < (user.borrowAmount * LIQUIDATION_THRESHOLD) / 1e18
        ) {
            revert LendingPool__WithdrawExceedsThreshold();
        }

        user.depositAmount = uint128(user.depositAmount - amount);
        user.lastUpdateTime = uint64(block.timestamp);

        AssetInfo storage assetData = assetInfo[asset];
        assetData.totalDeposits -= amount;

        // 更新奖励债务
        user.rewardDebt = (user.depositAmount * accRewardPerShare[asset]) / 1e18;

        SafeERC20.safeTransfer(IERC20(asset), msg.sender, amount);

        updateAssetInfo(asset);
        emit Withdraw(asset, msg.sender, amount);
    }

    /// @notice 获取用户抵押品价值
    /// @param user 用户地址
    /// @return 总抵押品价值 (USD)
    /// @dev 获取用户所有存款的抵押品价值 价值 = 存款金额 * 抵押率 * 价格
    function getCollateralValue(address user) public view returns (uint256) {
        uint256 totalValue = 0;
        address[] memory assets = assetManager.getSupportedAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            UserInfo storage curUserInfo = userInfo[asset][user];

            if (curUserInfo.depositAmount > 0) {
                AssetManager.AssetConfig memory config = assetManager.getAssetConfig(asset);
                AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[asset]);
                (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
                uint256 assetValue = uint256(curUserInfo.depositAmount) * uint256(price);
                totalValue += (assetValue * config.collateralFactor) / 1e18;
            }
        }

        return totalValue;
    }

    function _handleLiquidationTransfers(
        address asset,
        address /* user */,
        address liquidator,
        uint256 repayAmount,
        uint256 bonus
    ) internal {
        SafeERC20.safeTransferFrom(IERC20(asset), liquidator, address(this), repayAmount);
        SafeERC20.safeTransfer(IERC20(asset), liquidator, repayAmount + bonus);
    }

    function _healthFactor(address user) private view returns (uint256) {
        uint256 totalCollateralValue = getCollateralValue(user);
        if (totalCollateralValue == 0) return 0;

        uint256 borrowValue = 0;
        address[] memory assets = assetManager.getSupportedAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            UserInfo storage userAsset = userInfo[asset][user];
            if (userAsset.borrowAmount > 0) {
                AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[asset]);
                (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
                uint256 assetValue = uint256(userAsset.borrowAmount) * uint256(price);
                borrowValue += assetValue;
            }
        }

        if (borrowValue == 0) return type(uint256).max;
        return (totalCollateralValue * PRECISION) / borrowValue;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getUserBorrowAmount(address user, address asset) external view returns (uint256) {
        return userInfo[asset][user].borrowAmount;
    }

    function getUserBorrowUsdValue(address user, address asset) public view returns (uint256) {
        uint256 borrowValue = 0;
        UserInfo storage userAsset = userInfo[asset][user];
        if (userAsset.borrowAmount > 0) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[asset]);
            (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
            uint256 assetValue = uint256(userAsset.borrowAmount) * uint256(price);
            borrowValue += assetValue;
        }
        return borrowValue;
    }

    /// @notice 获取用户当前的借款限额
    /// @param user 用户地址
    /// @param asset 资产地址
    /// @dev 借款数量 = (抵押品价值 - 已借款价值) * 借款因子 / （价格 * 1e18）
    function getUserBorrowLimit(address user, address asset) external view returns (uint256) {
        if (!assetManager.isAssetSupported(asset)) revert LendingPool__AssetNotSupported();

        uint256 collateralValue = getCollateralValue(user);
        if (collateralValue == 0) return 0;

        AssetManager.AssetConfig memory config = assetManager.getAssetConfig(asset);
        uint256 borrowedValue = getUserBorrowUsdValue(user, asset);

        if (borrowedValue >= collateralValue) return 0;

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[asset]);
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        uint256 availableValue = collateralValue - borrowedValue;
        uint256 borrowLimit = (availableValue * config.borrowFactor) / 1e18;

        return (borrowLimit * 1e18) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getBorrowValueUsd(
        address asset,
        uint256 borrowAmount
    ) external view returns (uint256) {
        if (borrowAmount == 0) return 0;
        uint256 borrowValue = 0;
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[asset]);
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        uint256 assetValue = uint256(borrowAmount) * uint256(price);
        borrowValue += assetValue;
        return borrowValue;
    }

    function getAccRewardPerShare(address asset) external view returns (uint256) {
        return accRewardPerShare[asset];
    }

    function getRewardPerBlock() external view returns (uint256) {
        return rewardPerBlock;
    }
}
