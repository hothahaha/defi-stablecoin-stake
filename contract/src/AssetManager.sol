// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title 资产管理合约
/// @notice 管理支持的资产及其配置
/// @dev 实现了资产配置的管理功能
contract AssetManager is Ownable {
    // Structs
    struct AssetConfig {
        bool isSupported; // 是否支持该资产
        uint256 collateralFactor; // 抵押率
        uint256 borrowFactor; // 借款率
        string symbol; // 代币符号
        string name; // 代币名称
        uint8 decimals; // 代币精度
        string icon; // 代币图标 URL
    }

    // State variables
    mapping(address => bool) public adders; // 创建权限映射
    mapping(address => AssetConfig) private s_assetConfigs; // 资产配置映射
    address[] private s_supportedAssets; // 支持的资产列表
    mapping(address => uint256) private assetReserves; // 添加储备金映射
    address public lendingPool;

    // Events
    event AssetAdded(address indexed asset, AssetConfig config);
    event AssetUpdated(address indexed asset, AssetConfig config);
    event AssetRemoved(address indexed asset);
    event ReservesAdded(address indexed asset, uint256 amount);
    event AdderStatusChanged(address indexed adder, bool status);

    // Errors
    error AssetManager__InvalidAsset();
    error AssetManager__AssetAlreadySupported();
    error AssetManager__AssetNotSupported();
    error AssetManager__InvalidFactor();
    error AssetManager__InvalidCaller();
    error AssetManager__InvalidAmount();
    error AssetManager__InvalidAdder(address adder);

    /// @notice 构造函数
    constructor() Ownable(msg.sender) {}

    modifier onlyLendingPool() {
        if (msg.sender != lendingPool) revert AssetManager__InvalidCaller();
        _;
    }

    function setLendingPool(address _lendingPool) external onlyOwner {
        if (_lendingPool == address(0)) revert AssetManager__InvalidAsset();
        lendingPool = _lendingPool;
    }

    /// @notice 添加新资产
    /// @param asset 资产地址
    /// @param config 资产配置
    function addAsset(address asset, AssetConfig memory config) external {
        if (!adders[msg.sender] && msg.sender != owner()) {
            revert AssetManager__InvalidAdder(msg.sender);
        }
        if (asset == address(0)) revert AssetManager__InvalidAsset();
        if (s_assetConfigs[asset].isSupported) revert AssetManager__AssetAlreadySupported();
        if (config.collateralFactor > 1e18) revert AssetManager__InvalidFactor();
        if (config.borrowFactor > 1e18) revert AssetManager__InvalidFactor();

        s_assetConfigs[asset] = config;
        s_supportedAssets.push(asset);
        emit AssetAdded(asset, config);
    }

    /// @notice 更新资产配置
    /// @param asset 资产地址
    /// @param config 新的资产配置
    function updateAsset(address asset, AssetConfig memory config) external onlyOwner {
        if (!s_assetConfigs[asset].isSupported) revert AssetManager__AssetNotSupported();
        if (config.collateralFactor > 1e18) revert AssetManager__InvalidFactor();
        if (config.borrowFactor > 1e18) revert AssetManager__InvalidFactor();

        s_assetConfigs[asset] = config;
        emit AssetUpdated(asset, config);
    }

    /// @notice 添加储备金
    /// @param asset 资产地址
    /// @param amount 储备金金额
    /// @dev 只能被 LendingPool 调用
    function addReserves(address asset, uint256 amount) external onlyLendingPool {
        if (!isAssetSupported(asset)) revert AssetManager__AssetNotSupported();
        if (amount == 0) revert AssetManager__InvalidAmount();

        // 更新储备金
        assetReserves[asset] += amount;

        emit ReservesAdded(asset, amount);
    }

    /// @notice 更新创建权限
    /// @param adder 创建者地址
    /// @param status 权限状态
    function updateAddRole(address adder, bool status) external onlyOwner {
        if (adder == address(0)) {
            revert AssetManager__InvalidAdder(adder);
        }

        adders[adder] = status;
        emit AdderStatusChanged(adder, status);
    }

    /// @notice 获取资产配置
    /// @param asset 资产地址
    /// @return 资产配置
    function getAssetConfig(address asset) external view returns (AssetConfig memory) {
        return s_assetConfigs[asset];
    }

    /// @notice 获取支持的资产列表
    /// @return 资产地址数组
    function getSupportedAssets() external view returns (address[] memory) {
        return s_supportedAssets;
    }

    /// @notice 检查资产是否支持
    /// @param asset 资产地址
    /// @return 是否支持
    function isAssetSupported(address asset) public view returns (bool) {
        return s_assetConfigs[asset].isSupported;
    }

    /// @notice 获取资产储备金
    /// @param asset 资产地址
    /// @return 储备金金额
    function getAssetReserves(address asset) external view returns (uint256) {
        return assetReserves[asset];
    }
}
