// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DecentralizedStableCoin
 * @author Galahad
 * @notice 这是一个与美元挂钩的去中心化稳定币
 * @dev 这个合约是ERC20实现，由MSCEngine控制铸造和销毁
 */
contract DecentralizedStableCoin is ERC20, Pausable, Ownable, ReentrancyGuard {
    // Type declarations
    struct DailyMint {
        uint128 amount; // 每日铸币上限
        uint64 timestamp; // 日期
        bool processed; // 打包到同一个存储槽
    }

    // State variables
    // Constants
    uint256 private constant DAILY_SECONDS = 1 days;
    uint256 private constant INITIAL_DAILY_LIMIT = 1_000_000 ether; // 使用ether关键字更清晰
    uint256 private constant MAX_DAILY_LIMIT = 10_000_000 ether;

    // Mutable state variables
    mapping(address => bool) public minters; // 铸币权限映射
    mapping(address => bool) public blacklisted; // 黑名单映射
    mapping(uint256 => DailyMint) private dailyMints;
    mapping(uint256 => uint256) public dailyMintAmount; // 每日铸币计数
    uint256 public dailyMintLimit; // 每日铸币限额

    // Events
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event Blacklisted(address indexed account);
    event BlacklistRemoved(address indexed account);
    event DailyLimitUpdated(uint256 indexed oldLimit, uint256 indexed newLimit);
    event MinterStatusChanged(address indexed minter, bool indexed status);

    // Errors
    error DecentralizedStableCoin__NotMinter();
    error DecentralizedStableCoin__Blacklisted();
    error DecentralizedStableCoin__DailyLimitExceeded();
    error DecentralizedStableCoin__InvalidAmount();
    error DecentralizedStableCoin__AlreadyMinter();
    error DecentralizedStableCoin__AlreadyBlacklisted();
    error DecentralizedStableCoin__NotBlacklisted();
    error DecentralizedStableCoin__ExceedsDailyLimit(uint256 requested, uint256 remaining);
    error DecentralizedStableCoin__InvalidMinter(address minter);
    error DecentralizedStableCoin__InvalidDailyLimit(uint256 limit);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {
        dailyMintLimit = INITIAL_DAILY_LIMIT;
    }

    /// @notice 暂停所有转账
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice 恢复所有转账
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice 添加黑名单
    /// @param account 账户地址
    function blacklist(address account) external onlyOwner {
        blacklisted[account] = true;
        emit Blacklisted(account);
    }

    /// @notice 添加黑名单
    /// @param account 账户地址
    function addToBlacklist(address account) external onlyOwner {
        if (blacklisted[account]) {
            revert DecentralizedStableCoin__AlreadyBlacklisted();
        }
        blacklisted[account] = true;
        emit Blacklisted(account);
    }

    /// @notice 移除黑名单
    /// @param account 账户地址
    function removeFromBlacklist(address account) external onlyOwner {
        if (!blacklisted[account]) {
            revert DecentralizedStableCoin__NotBlacklisted();
        }
        blacklisted[account] = false;
        emit BlacklistRemoved(account);
    }

    /// @notice 铸币
    /// @param to 接收地址
    /// @param amount 铸币数量
    function mint(address to, uint256 amount) external nonReentrant whenNotPaused returns (bool) {
        if (!minters[msg.sender]) {
            revert DecentralizedStableCoin__InvalidMinter(msg.sender);
        }
        if (blacklisted[to]) {
            revert DecentralizedStableCoin__Blacklisted();
        }
        if (amount == 0) {
            revert DecentralizedStableCoin__InvalidAmount();
        }

        // uint256 currentDay = block.timestamp / DAILY_SECONDS;
        // DailyMint storage dailyMint = dailyMints[currentDay];
        // uint256 newDailyTotal = dailyMint.amount + amount;
        // if (newDailyTotal > dailyMintLimit) {
        //     revert DecentralizedStableCoin__ExceedsDailyLimit(
        //         amount,
        //         dailyMintLimit - dailyMint.amount
        //     );
        // }

        // // 更新状态
        // dailyMint.amount = uint128(newDailyTotal); // 安全转换
        // dailyMint.timestamp = uint64(block.timestamp);

        // 铸币
        _mint(to, amount);
        return true;
    }

    /// @notice 销毁代币
    /// @param amount 销毁数量
    function burn(uint256 amount) external nonReentrant whenNotPaused {
        if (blacklisted[msg.sender]) {
            revert DecentralizedStableCoin__Blacklisted();
        }
        if (amount == 0) {
            revert DecentralizedStableCoin__InvalidAmount();
        }
        _burn(msg.sender, amount);
    }

    /// @notice 更新每日铸币限额
    /// @param newLimit 新的限额
    function updateDailyLimit(uint256 newLimit) external onlyOwner {
        if (newLimit > MAX_DAILY_LIMIT) {
            revert DecentralizedStableCoin__InvalidDailyLimit(newLimit);
        }

        emit DailyLimitUpdated(dailyMintLimit, newLimit);
        dailyMintLimit = newLimit;
    }

    /// @notice 更新铸币权限
    /// @param minter 铸币者地址
    /// @param status 权限状态
    function updateMinter(address minter, bool status) external onlyOwner {
        if (minter == address(0)) {
            revert DecentralizedStableCoin__InvalidMinter(minter);
        }

        minters[minter] = status;
        emit MinterStatusChanged(minter, status);
    }

    /// @notice 转账更新钩子
    /// @param from 发送方地址
    /// @param to 接收方地址
    /// @param amount 转账金额
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override whenNotPaused {
        if (blacklisted[from] || blacklisted[to]) {
            revert DecentralizedStableCoin__Blacklisted();
        }

        // 检查每日限额（如果是铸币操作）
        if (from == address(0)) {
            uint256 currentDay = block.timestamp / DAILY_SECONDS;
            DailyMint storage dailyMint = dailyMints[currentDay];
            if (dailyMint.amount + amount > dailyMintLimit) {
                revert DecentralizedStableCoin__ExceedsDailyLimit(
                    amount,
                    dailyMintLimit - dailyMint.amount
                );
            }
            dailyMint.amount = uint128(dailyMint.amount + amount);
        }

        super._update(from, to, amount);
    }
}
