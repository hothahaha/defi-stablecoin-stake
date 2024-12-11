// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IApi3ReaderProxy} from "@api3/contracts/interfaces/IApi3ReaderProxy.sol";

error API3Feed__InvalidProxy();
error API3Feed__StalePrice();
error API3Feed__ValueNotPositive();

contract API3Feed {
    uint256 public constant HEARTBEAT_INTERVAL = 1 days;

    mapping(address => address) public proxies;

    constructor(address[] memory tokens, address[] memory _proxies) {
        for (uint i = 0; i < tokens.length; i++) {
            proxies[tokens[i]] = _proxies[i];
        }
    }

    function getPrice(address token) external view returns (uint256 price, uint256 timestamp) {
        address proxy = proxies[token];
        if (proxy == address(0)) revert API3Feed__InvalidProxy();

        (int224 value, uint256 _timestamp) = IApi3ReaderProxy(proxy).read();

        // 验证价格和时间戳
        if (value <= 0) revert API3Feed__ValueNotPositive();
        if (_timestamp + HEARTBEAT_INTERVAL < block.timestamp) revert API3Feed__StalePrice();

        price = uint256(int256(value));
        timestamp = _timestamp;
    }
}
