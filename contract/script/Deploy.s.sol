// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {MantleStableCoin} from "../src/MantleStableCoin.sol";
import {MSCEngine} from "../src/MSCEngine.sol";
import {AssetManager} from "../src/AssetManager.sol";
import {InsurancePool} from "../src/InsurancePool.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {API3Feed} from "../src/price-feeds/API3Feed.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract DeployScript is Script {
    // 配置结构
    struct NetworkConfig {
        address[] collateralTokens;
        address[] priceFeeds;
        uint256 rewardPerBlock;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant USDC_USD_PRICE = 1e8;
    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // 获取网络配置
    function getNetworkConfig() public returns (NetworkConfig memory) {
        if (block.chainid == 5003) {
            // Mantle Testnet
            return getMantleTestnetConfig();
        } else {
            // Local
            return getLocalConfig();
        }
    }

    function getMantleTestnetConfig() internal view returns (NetworkConfig memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = 0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111; // ETH
        tokens[1] = 0x086a532583CdF6d9666c978Fa153B25816488CBb; // USDC

        address[] memory proxies = new address[](2);
        proxies[0] = 0xECd2Dd0067832675a705FF9dcD2CB722Bce78213; // API3 ETH/USD proxy
        proxies[1] = 0xCf31E6d732f7823A6289927e2Ad2fb1BcfD42CbC; // API3 USDC/USD proxy

        return
            NetworkConfig({
                collateralTokens: tokens,
                priceFeeds: proxies,
                rewardPerBlock: 1e18,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function getLocalConfig() internal returns (NetworkConfig memory) {
        vm.startBroadcast();

        // 部署模拟代币
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH");
        MockERC20 usdc = new MockERC20("USD Coin", "USDC");

        // 设置 API3 代理地址
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);

        address[] memory proxies = new address[](2);
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator usdcUsdPriceFeed = new MockV3Aggregator(DECIMALS, USDC_USD_PRICE);
        proxies[0] = address(ethUsdPriceFeed); // API3 ETH/USD proxy
        proxies[1] = address(usdcUsdPriceFeed); // API3 USDC/USD proxy

        vm.stopBroadcast();

        return
            NetworkConfig({
                collateralTokens: tokens,
                priceFeeds: proxies,
                rewardPerBlock: 1e18,
                deployerKey: DEFAULT_ANVIL_KEY
            });
    }

    function run() external {
        NetworkConfig memory config = getNetworkConfig();

        vm.startBroadcast(config.deployerKey);

        // 1. 部署稳定币
        MantleStableCoin msc = new MantleStableCoin("Mantle Stable Coin", "MSC");

        // 2. 部署资产管理器
        AssetManager assetManager = new AssetManager();

        // 3. 部署保险池
        InsurancePool insurancePool = new InsurancePool();

        // 4. 部署稳定币引擎
        MSCEngine engine = new MSCEngine(config.collateralTokens, config.priceFeeds, address(msc));

        // 5. 部署借贷池
        LendingPool lendingPool = new LendingPool(
            address(insurancePool),
            address(msc),
            config.rewardPerBlock,
            address(assetManager),
            config.collateralTokens,
            config.priceFeeds
        );

        // 6. 设置权限
        msc.updateMinter(address(engine), true);
        msc.updateMinter(address(lendingPool), true);

        // 7. 初始化资产配置
        for (uint i = 0; i < config.collateralTokens.length; i++) {
            AssetManager.AssetConfig memory assetConfig = AssetManager.AssetConfig({
                isSupported: true,
                collateralFactor: 75e16, // 75%
                borrowFactor: 80e16, // 80%
                liquidationFactor: 5e16 // 5%
            });
            assetManager.addAsset(config.collateralTokens[i], assetConfig);
        }

        vm.stopBroadcast();

        // 保存部署信息
        string memory deploymentPath = string(
            abi.encodePacked("deployments/", vm.toString(block.chainid), ".json")
        );
        string memory deployment = vm.serializeAddress("deployment", "msc", address(msc));
        deployment = vm.serializeAddress("deployment", "engine", address(engine));
        deployment = vm.serializeAddress("deployment", "assetManager", address(assetManager));
        deployment = vm.serializeAddress("deployment", "insurancePool", address(insurancePool));
        deployment = vm.serializeAddress("deployment", "lendingPool", address(lendingPool));
        vm.writeJson(deployment, deploymentPath);
    }
}
