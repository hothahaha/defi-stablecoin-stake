// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mock ERC20
/// @notice 用于本地测试的 ERC20 代币模拟合约
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /// @notice 铸造代币
    /// @param amount 铸造数量
    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    /// @notice 领取测试代币
    /// @dev 每次可以领取 100 个代币
    function faucet() external {
        _mint(msg.sender, 100 * 10 ** decimals());
    }

    /// @notice 为指定地址铸造代币
    /// @param to 接收地址
    /// @param amount 铸造数量
    function mintTo(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
