import { LendingPoolABI, AssetManagerABI, StablecoinABI } from "./contract-abi";
import { Chain } from "@rainbow-me/rainbowkit";

export const LENDING_POOL_ADDRESS = "0x3e07ab355cFe7810097E416225670722610E2430"; // Fill in actual address after deployment
export const ASSET_MANAGER_ADDRESS = "0x2E54882bda6aeB74999Bd268044fde1E761Fb534";
export const STABLECOIN_ADDRESS = "0x...";
export const COLLATERAL_TOKEN_ADDRESS = "0x...";

export const lendingPoolConfig = {
    address: LENDING_POOL_ADDRESS as `0x${string}`, // Replace with actual contract address
    abi: LendingPoolABI,
} as const;

export const assetManagerConfig = {
    address: ASSET_MANAGER_ADDRESS as `0x${string}`,
    abi: AssetManagerABI,
} as const;

export const stablecoinConfig = {
    address: STABLECOIN_ADDRESS as `0x${string}`,
    abi: StablecoinABI,
} as const;

export const mantleSepolia = {
    id: 5003,
    name: "Mantle Sepolia",
    nativeCurrency: {
        decimals: 18,
        name: "MNT",
        symbol: "MNT",
    },
    rpcUrls: {
        default: { http: ["https://rpc.sepolia.mantle.xyz"] },
    },
    blockExplorers: {
        default: {
            name: "Mantle Sepolia Explorer",
            url: "https://explorer.sepolia.mantle.xyz",
            apiUrl: "https://explorer.sepolia.mantle.xyz/api",
        },
    },
    contracts: {
        multicall3: {
            address: "0xcA11bde05977b3631167028862bE2a173976CA11",
            blockCreated: 561333,
        },
    },
    testnet: true,
} as const satisfies Chain;

export const local = {
    id: 31337,
    name: "Local",
    nativeCurrency: {
        decimals: 18,
        name: "Ethereum",
        symbol: "ETH",
    },
    rpcUrls: {
        default: { http: ["http://127.0.0.1:8545"] },
        public: { http: ["http://127.0.0.1:8545"] },
    },
    blockExplorers: {
        default: {
            name: "Mantle Sepolia Explorer",
            url: "https://explorer.sepolia.mantle.xyz",
            apiUrl: "https://explorer.sepolia.mantle.xyz/api",
        },
    },
    testnet: true,
} as const satisfies Chain;
