// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

/**
 * @title DSCEngine
 * @author Galahad
 * @notice 这个合约管理稳定币的铸造和销毁
 * @dev 这个合约实现了超额抵押机制
 */
contract DSCEngine is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;
    struct UserAccount {
        uint256 amountDSCMinted;
        mapping(address token => uint256 amount) collateralDeposited;
    }

    // Constants
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 需要 200% 抵押率
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    // State variables
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => UserAccount account) private s_userAccounts;

    DecentralizedStableCoin private immutable i_msc;
    address[] private s_collateralTokens;

    // Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemFrom,
        address indexed redeemTo,
        address token,
        uint256 amount
    );
    event DSCMinted(address indexed user, uint256 amount);
    event DSCBurned(address indexed user, uint256 amount);

    // Errors
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__BreaksHealthFactor();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();

    // Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /// @notice 构造函数，初始化支持的抵押品和价格源
    /// @param tokenAddresses 支持的代币地址数组
    /// @param priceFeedAddresses 对应的价格源地址数组
    /// @param mscAddress DSC代币地址
    /// @dev 确保代币地址和价格源地址数组长度相同
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address mscAddress
    ) Ownable(msg.sender) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_msc = DecentralizedStableCoin(mscAddress);
    }

    /// @notice 存入抵押品并铸造 DSC
    /// @param tokenCollateralAddress 抵押品地址
    /// @param amountCollateral 抵押数量
    /// @param amountDSCToMint 要铸造的 DSC 数量
    /// @dev 检查健康因子确保抵押充足
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /// @notice 存入抵押品
    /// @param tokenCollateralAddress 抵押品地址
    /// @param amountCollateral 抵押数量
    /// @dev 更新用户抵押记录并转入抵押品
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        s_userAccounts[msg.sender].collateralDeposited[tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        IERC20(tokenCollateralAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
    }

    /// @notice 赎回抵押品并销毁 DSC
    /// @param tokenCollateralAddress 抵押品地址
    /// @param amountCollateral 赎回数量
    /// @param amountDSCToBurn 要销毁的 DSC 数量
    /// @dev 检查健康因子确保剩余抵押充足
    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) external {
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        burnDSC(amountDSCToBurn);
    }

    /// @notice 赎回抵押品
    /// @param tokenCollateralAddress 抵押品地址
    /// @param amountCollateral 赎回数量
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice 铸造 DSC
    /// @param amountDSCToMint 铸造数量
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        unchecked {
            s_userAccounts[msg.sender].amountDSCMinted += amountDSCToMint;
        }
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_msc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
        emit DSCMinted(msg.sender, amountDSCToMint);
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
    }

    /// @notice 清算
    /// @param collateral 抵押token的地址
    /// @param user 被清算用户
    /// @param debtToCover 需要偿还的债务
    /// @dev 检查健康因子确保清算条件满足
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) /
            LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice 销毁 DSC
    /// @param amountDSCToBurn 销毁数量
    /// @param onBehalfOf 被销毁用户
    /// @param mscFrom 销毁来源
    /// @dev 更新用户铸造的 DSC 数量并销毁 DSC
    function _burnDSC(uint256 amountDSCToBurn, address onBehalfOf, address mscFrom) private {
        unchecked {
            s_userAccounts[onBehalfOf].amountDSCMinted -= amountDSCToBurn;
        }
        IERC20(address(i_msc)).safeTransferFrom(mscFrom, address(this), amountDSCToBurn);
        i_msc.burn(amountDSCToBurn);
        emit DSCBurned(onBehalfOf, amountDSCToBurn);
    }

    /// @notice 赎回抵押品
    /// @param from 赎回来源
    /// @param to 赎回目标
    /// @param tokenCollateralAddress 抵押品地址
    /// @param amountCollateral 赎回数量
    /// @dev 更新用户抵押记录并转入赎回的抵押品
    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        unchecked {
            s_userAccounts[from].collateralDeposited[tokenCollateralAddress] -= amountCollateral;
        }
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        IERC20(tokenCollateralAddress).safeTransfer(to, amountCollateral);
    }

    /// @notice 获取用户账户信息
    /// @param user 用户地址
    /// @return totalDSCMinted 用户铸造的 DSC 数量
    /// @return collateralValueInUsd 用户账户抵押品总价值
    function _getAccountInformation(
        address user
    ) private view returns (uint256 totalDSCMinted, uint256 collateralValueInUsd) {
        totalDSCMinted = s_userAccounts[user].amountDSCMinted;
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /// @notice 计算健康因子
    /// @param user 用户地址
    /// @return 健康因子
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUsd);
    }

    /// @notice 计算健康因子
    /// @param totalDSCMinted 用户铸造的 DSC 数量
    /// @param collateralValueInUsd 用户账户抵押品总价值
    /// @return 健康因子
    function _calculateHealthFactor(
        uint256 totalDSCMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDSCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) /
            LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    /// @notice 检查健康因子是否破损
    /// @param user 用户地址
    /// @dev 如果健康因子低于最小值，则抛出错误
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor();
        }
    }

    /// @notice 获取用户账户抵押品价值
    /// @param user 用户地址
    /// @return totalCollateralValueInUsd 账户抵押品总价值
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_userAccounts[user].collateralDeposited[token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /// @notice 获取抵押品价值
    /// @param token 抵押品地址
    /// @param amount 抵押数量
    /// @return 抵押品价值
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /// @notice 获取抵押品价值
    /// @param token 抵押品地址
    /// @param usdAmountInWei 美元金额
    /// @return 抵押品价值
    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION); // API3 价格使用8位精度
    }

    /// @notice 获取用户账户信息
    /// @param user 用户地址
    /// @return totalDSCMinted 用户铸造的 DSC 数量
    /// @return collateralValueInUsd 用户账户抵押品总价值
    function getAccountInformation(
        address user
    ) external view returns (uint256 totalDSCMinted, uint256 collateralValueInUsd) {
        (totalDSCMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    /// @notice 获取用户健康因子
    /// @param user 用户地址
    /// @return 健康因子
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
