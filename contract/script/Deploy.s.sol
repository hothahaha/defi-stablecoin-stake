// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
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
        address[] memory tokens = new address[](2);
        tokens[0] = 0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111; // ETH
        tokens[1] = 0x086a532583CdF6d9666c978Fa153B25816488CBb; // USDC

        address[] memory proxies = new address[](2);
        proxies[0] = 0xECd2Dd0067832675a705FF9dcD2CB722Bce78213; // API3 ETH/USD proxy
        proxies[1] = 0xCf31E6d732f7823A6289927e2Ad2fb1BcfD42CbC; // API3 USDC/USD proxy

        return
            NetworkConfig({
                collateralTokens: tokens,
                priceFeeds: proxies,
                rewardPerBlock: 1e15,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function getLocalConfig() internal returns (NetworkConfig memory) {
        vm.startBroadcast(DEFAULT_ANVIL_KEY);
        // 部署模拟代币
        MockERC20 weth = new MockERC20("WETH", "ETH");
        MockERC20 usdc = new MockERC20("USD Tether", "USDT");

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
                rewardPerBlock: 1e15,
                deployerKey: DEFAULT_ANVIL_KEY
            });
    }

    function run() external {
        NetworkConfig memory config = getNetworkConfig();

        vm.startBroadcast(config.deployerKey);

        // 1. 部署稳定币
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(
            "Decentralized Stable Coin",
            "DSC"
        );

        // 2. 部署资产管理器
        AssetManager assetManager = new AssetManager();

        // 3. 部署保险池
        InsurancePool insurancePool = new InsurancePool();

        // 4. 部署稳定币引擎
        DSCEngine engine = new DSCEngine(config.collateralTokens, config.priceFeeds, address(dsc));

        // 5. 部署借贷池
        LendingPool lendingPool = new LendingPool(
            address(insurancePool),
            address(dsc),
            config.rewardPerBlock,
            address(assetManager),
            config.collateralTokens,
            config.priceFeeds
        );

        assetManager.setLendingPool(address(lendingPool));

        // 6. 设置权限
        dsc.updateMinter(address(engine), true);
        dsc.updateMinter(address(lendingPool), true);
        assetManager.updateAddRole(address(lendingPool), true);

        // 7. 初始化资产配置
        for (uint i = 0; i < config.collateralTokens.length; i++) {
            string memory symbol = i == 0 ? "ETH" : "USDT";
            string memory name = i == 0 ? "WETH" : "USD Tether";
            uint8 decimals = i == 0 ? 18 : 18;
            string memory icon = i == 0
                ? "https://assets.coingecko.com/coins/images/279/small/ethereum.png"
                : "https://assets.coingecko.com/coins/images/325/small/Tether.png";

            AssetManager.AssetConfig memory assetConfig = AssetManager.AssetConfig({
                isSupported: true,
                collateralFactor: 75e16, // 75%
                borrowFactor: 80e16, // 80%
                symbol: symbol,
                name: name,
                decimals: decimals,
                icon: icon
            });
            assetManager.addAsset(config.collateralTokens[i], assetConfig);
            // 打印每个资产的添加
            console.log("Added asset to AssetManager:", config.collateralTokens[i]);
        }

        vm.stopBroadcast();

        // 保存部署信息
        console.log("Deployment Addresses:");
        console.log("DSC:", address(dsc));
        console.log("Engine:", address(engine));
        console.log("AssetManager:", address(assetManager));
        console.log("InsurancePool:", address(insurancePool));
        console.log("LendingPool:", address(lendingPool));

        // 验证支持的资产
        address[] memory supportedAssets = assetManager.getSupportedAssets();
        console.log("\nSupported Assets:");
        for (uint i = 0; i < supportedAssets.length; i++) {
            console.log(string.concat("Asset ", vm.toString(i), ":"), supportedAssets[i]);

            // 获取并打印资产配置
            AssetManager.AssetConfig memory config1 = assetManager.getAssetConfig(
                supportedAssets[i]
            );
            console.log("Symbol:", config1.symbol);
            console.log("Name:", config1.name);
        }
    }
}
