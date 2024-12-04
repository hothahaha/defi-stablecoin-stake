// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AssetManager} from "../../src/AssetManager.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract AssetManagerTest is Test {
    AssetManager public assetManager;
    MockERC20 public weth;
    MockERC20 public usdc;
    address public owner;
    address public user;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        vm.startPrank(owner);

        assetManager = new AssetManager();
        weth = new MockERC20("Wrapped ETH", "WETH");
        usdc = new MockERC20("USD Coin", "USDC");

        vm.stopPrank();
    }

    function testAddAsset() public {
        vm.startPrank(owner);

        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16, // 75%
            borrowFactor: 80e16, // 80%
            liquidationFactor: 5e16 // 5%
        });

        vm.expectEmit(true, false, false, true);
        emit AssetManager.AssetAdded(address(weth), config);

        assetManager.addAsset(address(weth), config);

        AssetManager.AssetConfig memory savedConfig = assetManager.getAssetConfig(address(weth));
        assertEq(savedConfig.isSupported, true);
        assertEq(savedConfig.collateralFactor, 75e16);
        assertEq(savedConfig.borrowFactor, 80e16);
        assertEq(savedConfig.liquidationFactor, 5e16);

        vm.stopPrank();
    }

    function testCannotAddAssetWithInvalidFactors() public {
        vm.startPrank(owner);

        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 2e18, // 200%
            borrowFactor: 80e16,
            liquidationFactor: 5e16
        });

        vm.expectRevert(AssetManager.AssetManager__InvalidFactor.selector);
        assetManager.addAsset(address(weth), config);

        vm.stopPrank();
    }

    function testCannotAddZeroAddress() public {
        vm.startPrank(owner);

        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16,
            borrowFactor: 80e16,
            liquidationFactor: 5e16
        });

        vm.expectRevert(AssetManager.AssetManager__InvalidAsset.selector);
        assetManager.addAsset(address(0), config);

        vm.stopPrank();
    }

    function testCannotAddDuplicateAsset() public {
        vm.startPrank(owner);

        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16,
            borrowFactor: 80e16,
            liquidationFactor: 5e16
        });

        assetManager.addAsset(address(weth), config);

        vm.expectRevert(AssetManager.AssetManager__AssetAlreadySupported.selector);
        assetManager.addAsset(address(weth), config);

        vm.stopPrank();
    }

    function testUpdateAsset() public {
        vm.startPrank(owner);

        // First add the asset
        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16,
            borrowFactor: 80e16,
            liquidationFactor: 5e16
        });
        assetManager.addAsset(address(weth), config);

        // Update the config
        AssetManager.AssetConfig memory newConfig = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 70e16,
            borrowFactor: 75e16,
            liquidationFactor: 6e16
        });

        vm.expectEmit(true, false, false, true);
        emit AssetManager.AssetUpdated(address(weth), newConfig);

        assetManager.updateAsset(address(weth), newConfig);

        AssetManager.AssetConfig memory savedConfig = assetManager.getAssetConfig(address(weth));
        assertEq(savedConfig.collateralFactor, 70e16);
        assertEq(savedConfig.borrowFactor, 75e16);
        assertEq(savedConfig.liquidationFactor, 6e16);

        vm.stopPrank();
    }

    function testCannotUpdateNonexistentAsset() public {
        vm.startPrank(owner);

        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16,
            borrowFactor: 80e16,
            liquidationFactor: 5e16
        });

        vm.expectRevert(AssetManager.AssetManager__AssetNotSupported.selector);
        assetManager.updateAsset(address(weth), config);

        vm.stopPrank();
    }

    function testGetSupportedAssets() public {
        vm.startPrank(owner);

        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16,
            borrowFactor: 80e16,
            liquidationFactor: 5e16
        });

        assetManager.addAsset(address(weth), config);
        assetManager.addAsset(address(usdc), config);

        address[] memory assets = assetManager.getSupportedAssets();
        assertEq(assets.length, 2);
        assertEq(assets[0], address(weth));
        assertEq(assets[1], address(usdc));

        vm.stopPrank();
    }

    function testIsAssetSupported() public {
        vm.startPrank(owner);

        AssetManager.AssetConfig memory config = AssetManager.AssetConfig({
            isSupported: true,
            collateralFactor: 75e16,
            borrowFactor: 80e16,
            liquidationFactor: 5e16
        });

        assetManager.addAsset(address(weth), config);

        assertTrue(assetManager.isAssetSupported(address(weth)));
        assertFalse(assetManager.isAssetSupported(address(usdc)));

        vm.stopPrank();
    }
}
