// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title 资产管理合约
/// @notice 管理支持的资产及其配置
/// @dev 实现了资产配置的管理功能
contract AssetManager is Ownable {
    // Structs
    struct AssetConfig {
        bool isSupported;         // 是否支持该资产
        uint256 collateralFactor; // 抵押率
        uint256 borrowFactor;     // 借款率
        uint256 liquidationFactor; // 清算率
    }

    // State variables
    mapping(address => AssetConfig) private s_assetConfigs;  // 资产配置映射
    address[] private s_supportedAssets;  // 支持的资产列表

    // Events
    event AssetAdded(address indexed asset, AssetConfig config);
    event AssetUpdated(address indexed asset, AssetConfig config);
    event AssetRemoved(address indexed asset);

    // Errors
    error AssetManager__InvalidAsset();
    error AssetManager__AssetAlreadySupported();
    error AssetManager__AssetNotSupported();
    error AssetManager__InvalidFactor();

    /// @notice 构造函数
    constructor() Ownable(msg.sender) {}

    /// @notice 添加新资产
    /// @param asset 资产地址
    /// @param config 资产配置
    function addAsset(address asset, AssetConfig memory config) external onlyOwner {
        if (asset == address(0)) revert AssetManager__InvalidAsset();
        if (s_assetConfigs[asset].isSupported) revert AssetManager__AssetAlreadySupported();
        if (config.collateralFactor > 1e18) revert AssetManager__InvalidFactor();
        if (config.borrowFactor > 1e18) revert AssetManager__InvalidFactor();
        if (config.liquidationFactor > 1e18) revert AssetManager__InvalidFactor();

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
        if (config.liquidationFactor > 1e18) revert AssetManager__InvalidFactor();

        s_assetConfigs[asset] = config;
        emit AssetUpdated(asset, config);
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
    function isAssetSupported(address asset) external view returns (bool) {
        return s_assetConfigs[asset].isSupported;
    }
}
