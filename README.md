# 项目概述

专注于 Mantle 的低 Gas 和高效率特性，同时通过动态利率和保险机制创新，提升用户体验和资本利用率，避免跨链复杂性。

# 核心功能

1. 多资产借贷市场

-   支持 Mantle 原生代币（如 $MNT）和其他主流资产（ETH、USDT 等）的借贷服务。通过链上实时数据，动态调整不同资产的抵押率和清算风险

2. 无清算损失抵押机制
   引入保险池（Insurance Pool），通过保费收取（存款利率的一小部分），在清算时为用户提供部分补偿，降低清算后的损失。
3. 动态利率模型
   使用以下公式实时计算利率：

-   利用率（Utilization Rate） = 借款金额 / 池内存款总量
-   利率随利用率动态变化，使用曲线模型：

```
利率 = Base Rate + (Utilization Rate^2 * Multiplier)
```

高利用率时，借款利率陡增，鼓励用户存款。

4. 流动性挖矿奖励

引入 $MNT 激励用户参与存款与借贷，增强平台早期流动性。

5. 时间加权收益增强

对长时间提供流动性的用户给予更高的奖励，鼓励资金长期锁定，稳定池内流动性。

# 技术实现细节

1. 核心智能合约

-   借贷池合约：管理存款、借款、还款逻辑。
-   动态利率模型合约：实时计算每种资产的利率。
-   保险池合约：存储保费，提供清算损失补偿。

2. 前端设计

-   使用 React + Mantle 提供的 Web3 SDK（如 ethers.js）实现用户界面。
-   提供可视化的利率曲线、资产净值变化图表。

3. 链上数据支持

-   集成 Mantle 提供的预言机服务或 Chainlink（如果 Mantle 支持），实时获取资产价格和市场数据。

4. 安全审计

-   利用 Foundry 测试合约安全性。
-   提供全面的测试覆盖，包括极端利用率测试和清算场景。

# 文档

# 项目结构

mantle-defi-stablecoin
├── contract
│ ├── README.md
│ ├── foundry.toml
│ ├── lib
│ ├── script
│ ├── src
│ │ ├── libraries
│ │ └── \*.sol
│ └── test
├── frontend
│ ├── README.md
│ ├── components.json
│ ├── next-env.d.ts
│ ├── next.config.mjs
│ ├── node_modules
│ ├── package-lock.json
│ ├── package.json
│ ├── postcss.config.mjs
│ ├── src
│ ├── tailwind.config.ts
│ └── tsconfig.json
└── instructions
└── 说明.md

# 注意事项

1. require 改为 revert
2. 注释使用中文
3. 根据官方规范布局调整代码
4. 使用最优化 gas 的方式和最佳实践来生成代码
