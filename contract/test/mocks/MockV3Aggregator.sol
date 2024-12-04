// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title MockV3Aggregator
 * @notice 用于测试的 Chainlink 价格预言机模拟合约
 */
contract MockV3Aggregator {
    uint8 public immutable decimals;
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint80 public latestRound;

    mapping(uint80 => int256) public getAnswer;
    mapping(uint80 => uint256) public getTimestamp;
    mapping(uint80 => uint256) private getStartedAt;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
    }

    function updateAnswer(int256 _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestRound++;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = block.timestamp;
        getStartedAt[latestRound] = block.timestamp;
    }

    function updateRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _timestamp,
        uint256 _startedAt
    ) public {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = _timestamp;
        getStartedAt[latestRound] = _startedAt;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            _roundId,
            getAnswer[_roundId],
            getStartedAt[_roundId],
            getTimestamp[_roundId],
            _roundId
        );
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            latestRound,
            latestAnswer,
            getStartedAt[latestRound],
            latestTimestamp,
            latestRound
        );
    }

    function description() external pure returns (string memory) {
        return "v0.8/tests/MockV3Aggregator.sol";
    }

    function version() external pure returns (uint256) {
        return 0;
    }
} 