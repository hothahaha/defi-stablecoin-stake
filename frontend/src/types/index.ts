export interface AssertManagerInfo {
    totalDeposits: bigint;
    totalBorrows: bigint;
    lastUpdateTime: bigint;
    currentRate: bigint;
    borrowRate: bigint;
    depositRate: bigint;
    reserveFactor: bigint;
    borrowIndex: bigint;
    depositIndex: bigint;
}

export interface Asset {
    token: `0x${string}`;
    config: AssetConfig;
    info: AssertManagerInfo;
    price: bigint;
}

export interface UserAsset {
    token: `0x${string}`;
    symbol: string;
    name: string;
    decimals: number;
    icon: string;
    depositAmount?: bigint;
    borrowAmount?: bigint;
    config: AssetConfig;
}

export interface AssetConfig {
    isSupported: boolean; // 是否支持该资产
    collateralFactor: bigint; // 抵押率
    borrowFactor: bigint; // 借款率
    symbol: string; // 代币符号
    name: string; // 代币名称
    decimals: number; // 代币精度
    icon: string; // 代币图标 URL
}

export interface AssetData {
    totalSupply: bigint;
    totalBorrow: bigint;
    supplyApy: bigint;
    borrowApy: bigint;
}
