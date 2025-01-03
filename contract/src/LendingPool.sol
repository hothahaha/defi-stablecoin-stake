// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Api3ReaderProxyV1} from "@api3/contracts/api3-server-v1/proxies/Api3ReaderProxyV1.sol";

import {InterestRateModel} from "./libraries/InterestRateModel.sol";
import {TimeWeightedRewards} from "./libraries/TimeWeightedRewards.sol";
import {InsurancePool} from "./InsurancePool.sol";
import {AssetManager} from "./AssetManager.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

/// @title 借贷池合约
/// @notice 管理存款、借款和还款业务
contract LendingPool is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    // Type declarations
    struct UserInfo {
        uint128 depositAmount; // 用户存款金额
        uint128 borrowAmount; // 用户借款金额
        uint64 lastUpdateTime; // 最后更新时间
        uint256 rewardDebt; // 奖励债务
        uint256 borrowIndex; // 用户借款指数
        uint256 depositIndex; // 用户存款指数
    }

    struct AssetInfo {
        uint256 totalDeposits; // 总存款
        uint256 totalBorrows; // 总借款
        uint64 lastUpdateTime; // 最后更新时间
        uint256 currentRate; // 当前利率
        uint256 borrowRate; // 借款利率
        uint256 depositRate; // 存款利率
        uint256 reserveFactor; // 储备金率
        uint256 borrowIndex; // 借款指数
        uint256 depositIndex; // 存款指数
    }

    // State variables
    // Constants
    uint256 private constant PRECISION = 1e18;

    // Immutable state variables
    InsurancePool public immutable insurancePool; // 保险池合约
    AssetManager public immutable assetManager; // 资产管理器
    DecentralizedStableCoin public immutable dsc; // 去中心化稳定币

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
    event AssetAdded(address indexed token, address indexed priceFeed);
    event RewardClaimed(address indexed asset, address indexed user, uint256 amount);

    // Errors
    error LendingPool__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error LendingPool__InvalidAmount();
    error LendingPool__InsufficientCollateral();
    error LendingPool__NotLiquidatable();
    error LendingPool__WithdrawalExceedsThreshold();
    error LendingPool__ExceedsMaxBorrowFactor();
    error LendingPool__InvalidCollateralFactor();
    error LendingPool__ExceedsAvailableLiquidity(uint256 requested, uint256 available);
    error LendingPool__InvalidCollateralRatio(uint256 current, uint256 required);
    error LendingPool__TransferFailed();
    error LendingPool__HealthFactorOk();
    error LendingPool__HealthFactorNotImproved();
    error LendingPool__InsufficientBalance();
    error LendingPool__WithdrawExceedsThreshold();
    error LendingPool__AssetAlreadySupported();
    error LendingPool__InvalidAddress();
    error LendingPool__MintFailed();

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
        rewardPerBlock = _rewardPerBlock;
        lastRewardBlock = block.number;
        assetManager = AssetManager(_assetManager);
        dsc = DecentralizedStableCoin(_rewardToken);

        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert LendingPool__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_assertTokens.push(tokenAddresses[i]);

            // 初始化资产信息
            assetInfo[tokenAddresses[i]] = AssetInfo({
                totalDeposits: 0,
                totalBorrows: 0,
                lastUpdateTime: uint64(block.timestamp),
                currentRate: InterestRateModel.calculateInterestRate(0, 0),
                borrowRate: 0,
                depositRate: 0,
                reserveFactor: 1e17, // 10% 储备金率
                borrowIndex: 1e18, // 初始指数
                depositIndex: 1e18 // 初始指数
            });
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

    /// @notice 存款
    /// @param asset 资产地址
    /// @param amount 存款金额
    /// @dev
    function deposit(address asset, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) {
            revert LendingPool__InvalidAmount();
        }

        // 更新资产信息和奖励
        updateAssetInfo(asset);

        UserInfo storage user = userInfo[asset][msg.sender];
        AssetInfo storage assetData = assetInfo[asset];

        // 如果用户已有存款，计算累积利息
        uint256 accruedInterest = 0;
        if (user.depositAmount > 0) {
            accruedInterest = _calculateAccruedInterest(
                user.depositAmount,
                user.depositIndex,
                assetData.depositIndex
            );
        }

        // 更新实际存款金额（包含利息）
        uint256 newDepositAmount = user.depositAmount + amount + accruedInterest;
        user.depositAmount = uint128(newDepositAmount);

        // 计算时间加权金额（仅用于奖励计算）
        uint256 weightedAmount;
        if (user.depositAmount > 0 && user.lastUpdateTime > 0) {
            // 计算现有存款的时间加权金额
            weightedAmount = TimeWeightedRewards.calculateWeightedAmount(
                user.depositAmount,
                user.lastUpdateTime,
                block.timestamp
            );
        } else {
            weightedAmount = amount;
        }
        // 更新时间戳
        user.lastUpdateTime = uint64(block.timestamp);

        // 执行转账
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // 更新奖励债务（代币奖励）
        uint256 pending = (weightedAmount * accRewardPerShare[asset]) / PRECISION - user.rewardDebt;
        if (pending > 0) {
            bool success = dsc.mint(msg.sender, pending);
            if (!success) {
                revert LendingPool__MintFailed();
            }
        }
        user.rewardDebt = (weightedAmount * accRewardPerShare[asset]) / PRECISION;

        // 更新用户存款指数
        user.depositIndex = assetData.depositIndex;

        // 更新总存款
        assetData.totalDeposits += amount + accruedInterest;

        emit Deposit(asset, msg.sender, amount, block.timestamp);
    }

    /// @notice 借款
    /// @param asset 资产地址
    /// @param amount 借款金额
    /// @dev 借款前需要先存款
    function borrow(address asset, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) {
            revert LendingPool__InvalidAmount();
        }

        // 更新资产信息和奖励
        updateAssetInfo(asset);

        UserInfo storage user = userInfo[asset][msg.sender];
        AssetInfo storage assetData = assetInfo[asset];

        // 如果用户已有借款，计算累积利息
        if (user.borrowAmount > 0) {
            uint256 borrowInterest = _calculateAccruedInterest(
                user.borrowAmount,
                user.borrowIndex,
                assetData.borrowIndex
            );
            user.borrowAmount += uint128(borrowInterest);
            assetData.totalBorrows += borrowInterest;
        }

        // 获取资产价格并计算可借款价值
        (, int256 price, , , ) = Api3ReaderProxyV1(s_priceFeeds[asset]).latestRoundData();
        uint256 currentBorrowValueUSD = (user.borrowAmount * uint256(price)) / PRECISION;
        uint256 newBorrowValueUSD = (amount * uint256(price)) / PRECISION;
        uint256 borrowLimitUSD = getUserBorrowLimitInUSD(msg.sender);

        // 检查总借款价值是否超过限额
        if (currentBorrowValueUSD + newBorrowValueUSD > borrowLimitUSD) {
            revert LendingPool__ExceedsMaxBorrowFactor();
        }
        // 更新用户借款信息
        user.borrowAmount = uint128(user.borrowAmount + amount);
        user.borrowIndex = assetData.borrowIndex;
        user.lastUpdateTime = uint64(block.timestamp);

        // 更新资产总借款金额
        assetData.totalBorrows += amount;

        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Borrow(asset, msg.sender, amount);
    }

    /// @notice 还款
    /// @param asset 资产地址
    /// @param amount 还款金额
    function repay(address asset, uint256 amount) external nonReentrant {
        if (amount == 0) revert LendingPool__InvalidAmount();

        updateAssetInfo(asset);

        UserInfo storage user = userInfo[asset][msg.sender];
        AssetInfo storage assetData = assetInfo[asset];

        // 先计算累积的借款利息
        uint256 borrowInterest = _calculateAccruedInterest(
            user.borrowAmount,
            user.borrowIndex,
            assetData.borrowIndex
        );

        // 计算总债务
        uint256 totalDebt = user.borrowAmount + borrowInterest;
        if (totalDebt == 0) revert LendingPool__InvalidAmount();

        // 计算实际还款金额
        uint256 actualRepayAmount = amount > totalDebt ? totalDebt : amount;

        // 更新用户借款金额
        user.borrowAmount = uint128(totalDebt - actualRepayAmount);
        user.borrowIndex = assetData.borrowIndex;
        user.lastUpdateTime = uint64(block.timestamp);

        // 更新总借款金额
        assetData.totalBorrows = assetData.totalBorrows + borrowInterest - actualRepayAmount;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), actualRepayAmount);

        emit Repay(asset, msg.sender, actualRepayAmount);
    }

    /// @notice 更新并领取奖励
    /// @param asset 资产地址
    function claimReward(address asset) external nonReentrant {
        updateAssetInfo(asset);
        UserInfo storage user = userInfo[asset][msg.sender];

        // 计算累积的存款利息
        uint256 depositInterest = _calculateAccruedInterest(
            user.depositAmount,
            user.depositIndex,
            assetInfo[asset].depositIndex
        );

        // 计算时间加权金额
        uint256 weightedAmount = TimeWeightedRewards.calculateWeightedAmount(
            user.depositAmount + depositInterest,
            user.lastUpdateTime,
            block.timestamp
        );

        // 计算待领取奖励
        uint256 pending = (weightedAmount * accRewardPerShare[asset]) / PRECISION - user.rewardDebt;

        if (pending > 0) {
            // 更新用户状态
            user.depositIndex = assetInfo[asset].depositIndex;
            user.lastUpdateTime = uint64(block.timestamp);
            user.rewardDebt = (weightedAmount * accRewardPerShare[asset]) / PRECISION;

            // 铸造奖励
            dsc.mint(msg.sender, pending);

            emit RewardClaimed(asset, msg.sender, pending);
        }
    }

    /// @notice 更新资产信息和奖励
    /// @param asset 资产地址
    /// @dev 更新资产信息和奖励，获取区块奖励，计算存款的奖励份额
    function updateAssetInfo(address asset) internal {
        AssetInfo storage assetData = assetInfo[asset];
        uint256 _lastRewardBlock = lastRewardBlock;

        if (block.number > _lastRewardBlock) {
            uint256 reward;
            unchecked {
                uint256 multiplier = block.number - _lastRewardBlock;
                reward = multiplier * rewardPerBlock;
            }

            // 更新奖励份额
            if (assetData.totalDeposits > 0) {
                accRewardPerShare[asset] += (reward * PRECISION) / assetData.totalDeposits;
            }
        }

        // 计算累积利息
        uint256 timeElapsed = block.timestamp - assetData.lastUpdateTime;
        if (timeElapsed > 0) {
            // 更新借款指数
            if (assetData.totalBorrows > 0 && assetData.borrowRate > 0) {
                uint256 borrowInterest = InterestRateModel.calculateInterest(
                    assetData.totalBorrows,
                    assetData.borrowRate,
                    timeElapsed
                );
                if (borrowInterest > 0) {
                    // 更新借款指数
                    uint256 borrowIndexDelta = (borrowInterest * PRECISION) /
                        assetData.totalBorrows;
                    assetData.borrowIndex += borrowIndexDelta;

                    // 更新总借款金额
                    assetData.totalBorrows += borrowInterest;

                    // 计算储备金
                    uint256 reserveAmount = (borrowInterest * assetData.reserveFactor) / PRECISION;
                    assetManager.addReserves(asset, reserveAmount);

                    // 计算存款利息（总借款利息 - 储备金）
                    uint256 depositInterest = borrowInterest - reserveAmount;

                    if (assetData.totalDeposits > 0) {
                        uint256 depositIndexDelta = (depositInterest * PRECISION) /
                            assetData.totalDeposits;
                        assetData.depositIndex += depositIndexDelta;
                        assetData.totalDeposits += depositInterest;
                    }
                }
            }
        }

        // 更新借款利率和存款利率
        if (assetData.totalDeposits > 0) {
            assetData.borrowRate = InterestRateModel.calculateInterestRate(
                assetData.totalBorrows,
                assetData.totalDeposits
            );

            assetData.depositRate = InterestRateModel.calculateDepositRate(
                assetData.totalBorrows,
                assetData.totalDeposits,
                assetData.reserveFactor
            );
        }

        lastRewardBlock = block.number;
        assetData.lastUpdateTime = uint64(block.timestamp);

        emit AssetInfoUpdated(asset, assetData.currentRate, accRewardPerShare[asset]);
    }

    /// @notice 提取存款
    /// @param asset 资产地址
    /// @param amount 提取金额
    function withdraw(address asset, uint256 amount) external nonReentrant {
        updateAssetInfo(asset);

        UserInfo storage user = userInfo[asset][msg.sender];

        // 计算累积的存款利息
        uint256 depositInterest = _calculateAccruedInterest(
            user.depositAmount,
            user.depositIndex,
            assetInfo[asset].depositIndex
        );

        uint256 totalDeposit = user.depositAmount + depositInterest;
        if (totalDeposit < amount) {
            revert LendingPool__InsufficientBalance();
        }

        (, uint256 borrowedValue) = getUserTotalValueInUSD(msg.sender);
        // 检查提取后的抵押率
        if (
            // 如果用户有借款，需要 借款限额 > 借款额度
            borrowedValue > 0 && borrowedValue > getUserBorrowLimitInUSD(msg.sender)
        ) {
            revert LendingPool__WithdrawExceedsThreshold();
        }

        user.depositAmount = uint128(user.depositAmount - amount);
        user.depositIndex = assetInfo[asset].depositIndex;
        user.lastUpdateTime = uint64(block.timestamp);

        assetInfo[asset].totalDeposits -= amount;

        // 更新奖励债务
        user.rewardDebt = (user.depositAmount * accRewardPerShare[asset]) / PRECISION;

        IERC20(asset).safeTransfer(msg.sender, amount);

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
                Api3ReaderProxyV1 priceFeed = Api3ReaderProxyV1(s_priceFeeds[asset]);
                (, int256 price, , , ) = priceFeed.latestRoundData();
                uint256 assetValue = (uint256(curUserInfo.depositAmount) * uint256(price)) /
                    PRECISION;
                totalValue += (assetValue * config.collateralFactor) / PRECISION;
            }
        }

        return totalValue;
    }

    /// @notice 添加新的支持资产
    /// @param token 资产地址
    /// @param priceFeed 价格预言机地址
    /// @param config 资产配置
    function addAsset(
        address token,
        address priceFeed,
        AssetManager.AssetConfig calldata config
    ) external onlyOwner {
        // 检查资产是否已存在
        if (s_priceFeeds[token] != address(0)) {
            revert LendingPool__AssetAlreadySupported();
        }

        // 验证地址有效性
        if (token == address(0) || priceFeed == address(0)) {
            revert LendingPool__InvalidAddress();
        }

        // 添加价格预言机
        s_priceFeeds[token] = priceFeed;
        s_assertTokens.push(token);

        // 在资产管理器中添加资产
        assetManager.addAsset(token, config);

        // 初始化资产信息
        assetInfo[token] = AssetInfo({
            totalDeposits: 0,
            totalBorrows: 0,
            lastUpdateTime: uint64(block.timestamp),
            currentRate: InterestRateModel.calculateInterestRate(0, 0),
            borrowRate: 0,
            depositRate: 0,
            reserveFactor: 1e17, // 10% 储备金率
            borrowIndex: PRECISION, // 初始指数
            depositIndex: PRECISION // 初始指数
        });

        emit AssetAdded(token, priceFeed);
    }

    /// @notice 计算累积利息
    /// @param principal 本金
    /// @param userIndex 用户上次指数
    /// @param currentIndex 当前指数
    /// @return 累积的利息
    function _calculateAccruedInterest(
        uint256 principal,
        uint256 userIndex,
        uint256 currentIndex
    ) internal pure returns (uint256) {
        // 如果指数相同，说明没有新的利息
        if (userIndex == currentIndex) return 0;
        if (userIndex == 0) return 0;
        // 计算利息：本金 * (当前指数 / 用户上次指数 - 1)
        return (principal * (currentIndex - userIndex)) / userIndex;
    }

    /// @notice 获取用户借款数量
    /// @param user 用户地址
    /// @param asset 资产地址
    /// @return 借款数量
    function getUserBorrowAmount(address user, address asset) external view returns (uint256) {
        return userInfo[asset][user].borrowAmount;
    }

    /// @notice 获取用户借款价值
    /// @param asset 资产地址
    /// @param borrowAmount 借款数量
    /// @return 借款价值 (USD)
    function _getUserBorrowUsdValue(
        address asset,
        uint256 borrowAmount
    ) public view returns (uint256) {
        Api3ReaderProxyV1 priceFeed = Api3ReaderProxyV1(s_priceFeeds[asset]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 assetValue = ((uint256(borrowAmount) * uint256(price))) / PRECISION;
        return assetValue;
    }

    /// @notice 获取用户当前的借款限额
    /// @param user 用户地址
    /// @param asset 资产地址
    /// @dev 借款数量 = (抵押品价值 - 已借款价值) * 借款因子 / （价格 * 1e18）
    function getUserBorrowLimit(address user, address asset) public view returns (uint256) {
        // 获取最大借款限额
        uint256 borrowLimit = getUserBorrowLimitInUSD(user);

        // 获取当前已借款价值
        (, uint256 borrowedValue) = getUserTotalValueInUSD(user);
        if (borrowedValue >= borrowLimit) return 0;

        // 获取资产配置和价格
        Api3ReaderProxyV1 priceFeed = Api3ReaderProxyV1(s_priceFeeds[asset]);
        (, int256 price, , , ) = priceFeed.latestRoundData();

        uint256 availableValue = borrowLimit - borrowedValue;

        return (availableValue * PRECISION) / uint256(price);
    }

    /// @notice 获取资产价值
    /// @param asset 资产地址
    /// @param amount 资产数量
    /// @return 资产价值 (USD)
    function getValueUsdByAmount(address asset, uint256 amount) public view returns (uint256) {
        if (amount == 0) return 0;
        uint256 value = 0;
        Api3ReaderProxyV1 priceFeed = Api3ReaderProxyV1(s_priceFeeds[asset]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 assetValue = (uint256(amount) * uint256(price)) / PRECISION;
        value += assetValue;
        return value;
    }

    /// @notice 获取用户总借款价值
    /// @param user 用户地址
    function getUserTotalValueInUSD(
        address user
    ) public view returns (uint256 totalDepositValue, uint256 totalBorrowValue) {
        address[] memory assets = assetManager.getSupportedAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            UserInfo storage userAsset = userInfo[asset][user];
            if (userAsset.depositAmount > 0) {
                uint256 depositValue = getValueUsdByAmount(asset, userAsset.depositAmount);
                totalDepositValue += depositValue;
            }
            if (userAsset.borrowAmount > 0) {
                uint256 borrowValue = _getUserBorrowUsdValue(asset, userAsset.borrowAmount);
                totalBorrowValue += borrowValue;
            }
        }
    }

    /// @notice 获取用户总借款限额
    /// @param user 用户地址
    /// @return 总借款限额 (USD)
    function getUserBorrowLimitInUSD(address user) public view returns (uint256) {
        address[] memory assets = assetManager.getSupportedAssets();
        uint256 totalBorrowLimit = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            // 获取抵押品价值
            uint256 depositAmount = userInfo[asset][user].depositAmount;
            if (depositAmount > 0) {
                // 获取资产配置
                AssetManager.AssetConfig memory config = assetManager.getAssetConfig(asset);
                Api3ReaderProxyV1 priceFeed = Api3ReaderProxyV1(s_priceFeeds[asset]);
                (, int256 price, , , ) = priceFeed.latestRoundData();

                uint256 depositValue = (depositAmount * uint256(price)) / PRECISION;
                uint256 collateralValue = (depositValue * config.collateralFactor) / PRECISION;

                uint256 borrowLimitValue = (collateralValue * config.borrowFactor) / PRECISION;
                totalBorrowLimit += borrowLimitValue;
            }
        }
        return totalBorrowLimit;
    }

    /// @notice 获取用户最大可提取额度
    /// @param user 用户地址
    /// @param asset 资产地址
    /// @return 最大可提取额度
    function getMaxWithdrawAmount(address user, address asset) public view returns (uint256) {
        UserInfo memory userAsset = userInfo[asset][user];

        // 如果没有存款，直接返回0
        if (userAsset.depositAmount == 0) return 0;

        // 计算可提取的USD价值
        uint256 availableUSD = getMaxWithdrawAmountInUSD(user);
        if (availableUSD == 0) return 0;

        AssetManager.AssetConfig memory config = assetManager.getAssetConfig(asset);
        Api3ReaderProxyV1 priceFeed = Api3ReaderProxyV1(s_priceFeeds[asset]);
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // 转换为资产数量
        uint256 maxWithdraw = (availableUSD * PRECISION) / config.collateralFactor;
        maxWithdraw = (maxWithdraw * PRECISION) / config.borrowFactor;
        maxWithdraw = (maxWithdraw * PRECISION) / (uint256(price));
        return maxWithdraw;
    }

    /// @notice 获取用户最大可提取额度 (USD)
    /// @param user 用户地址
    /// @return 最大可提取额度 (USD)
    function getMaxWithdrawAmountInUSD(address user) public view returns (uint256) {
        (, uint256 currentBorrows) = getUserTotalValueInUSD(user);
        uint256 borrowLimit = getUserBorrowLimitInUSD(user);

        if (currentBorrows >= borrowLimit) return 0;
        return borrowLimit - currentBorrows;
    }

    /// @notice 获取资产的累积奖励
    /// @param asset 资产地址
    /// @return 累积奖励
    function getAccRewardPerShare(address asset) external view returns (uint256) {
        return accRewardPerShare[asset];
    }

    /// @notice 获取每个区块的奖励
    /// @return 每个区块的奖励
    function getRewardPerBlock() external view returns (uint256) {
        return rewardPerBlock;
    }

    /// @notice 获取资产信息
    /// @param asset 资产地址
    /// @return 资产信息
    function getAssetInfo(address asset) external view returns (AssetInfo memory) {
        return assetInfo[asset];
    }

    /// @notice 获取用户信息
    /// @param asset 资产地址
    /// @param user 用户地址
    /// @return 用户信息
    function getUserInfo(address asset, address user) external view returns (UserInfo memory) {
        return userInfo[asset][user];
    }

    function getPendingRewards(address user, address asset) external view returns (uint256) {
        UserInfo memory userAsset = userInfo[asset][user];
        uint256 weightedAmount = TimeWeightedRewards.calculateWeightedAmount(
            userAsset.depositAmount,
            userAsset.lastUpdateTime,
            block.timestamp
        );
        return (weightedAmount * accRewardPerShare[asset]) / PRECISION;
    }

    /// @notice 获取用户奖励债务
    /// @param user 用户地址
    /// @return totalRewardDebt 用户奖励债务
    /// @dev 计算当前存款的累积利息 - 用户已领的奖励
    function getUserRewardDebt(address user) external view returns (uint256 totalRewardDebt) {
        address[] memory assets = assetManager.getSupportedAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            AssetInfo memory assetInfoMemory = assetInfo[asset];
            UserInfo memory userInfoMemory = userInfo[asset][user];

            // 计算当前区块的累积奖励
            uint256 currentAccRewardPerShare = accRewardPerShare[asset];
            uint256 blocksSinceLastUpdate = block.timestamp - assetInfoMemory.lastUpdateTime;

            if (blocksSinceLastUpdate > 0 && assetInfoMemory.totalDeposits > 0) {
                currentAccRewardPerShare +=
                    (blocksSinceLastUpdate * rewardPerBlock * 1e18) /
                    assetInfoMemory.totalDeposits;
            }

            // 计算用户的奖励债务
            totalRewardDebt +=
                (userInfoMemory.depositAmount * currentAccRewardPerShare) /
                PRECISION -
                userInfoMemory.rewardDebt;
        }

        return totalRewardDebt;
    }

    /// @notice 获取总价值
    /// @return totalDeposits 总存款价值
    /// @return totalBorrows 总借款价值
    function getTotalValues() external view returns (uint256 totalDeposits, uint256 totalBorrows) {
        address[] memory assets = assetManager.getSupportedAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            totalDeposits += getValueUsdByAmount(asset, assetInfo[asset].totalDeposits);
            totalBorrows += _getUserBorrowUsdValue(asset, assetInfo[asset].totalBorrows);
        }
    }

    function getAssetPrice(address asset) public view returns (uint256) {
        Api3ReaderProxyV1 priceFeed = Api3ReaderProxyV1(s_priceFeeds[asset]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        if (price <= 0) return 0;
        return uint256(price);
    }
}
