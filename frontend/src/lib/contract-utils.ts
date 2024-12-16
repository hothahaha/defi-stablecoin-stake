import { ethers } from "ethers";
import { lendingPoolConfig, assetManagerConfig } from "./contract-config";

const ERC20_ABI = [
    {
        inputs: [
            {
                internalType: "address",
                name: "spender",
                type: "address",
            },
            {
                internalType: "uint256",
                name: "amount",
                type: "uint256",
            },
        ],
        name: "approve",
        outputs: [
            {
                internalType: "bool",
                name: "",
                type: "bool",
            },
        ],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "account",
                type: "address",
            },
        ],
        name: "balanceOf",
        outputs: [
            {
                internalType: "uint256",
                name: "",
                type: "uint256",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "owner",
                type: "address",
            },
            {
                internalType: "address",
                name: "spender",
                type: "address",
            },
        ],
        name: "allowance",
        outputs: [
            {
                internalType: "uint256",
                name: "",
                type: "uint256",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
] as const;

export function getProvider() {
    if (typeof window === "undefined") return null;
    if (!window.ethereum) {
        console.warn("No wallet found");
        return null;
    }
    return new ethers.BrowserProvider(window.ethereum);
}

export async function getSigner() {
    try {
        const provider = getProvider();
        if (!provider) return null;
        return await provider.getSigner();
    } catch (error) {
        console.warn("Failed to get signer:", error);
        return null;
    }
}

export function getLendingPoolContract(signerOrProvider?: ethers.Signer | ethers.Provider) {
    try {
        const provider = signerOrProvider || getProvider();
        if (!provider) return null;
        return new ethers.Contract(
            lendingPoolConfig.address,
            lendingPoolConfig.abi,
            provider
        );
    } catch (error) {
        console.warn("Failed to get lending pool contract:", error);
        return null;
    }
}

export function getAssetManagerContract(signerOrProvider?: ethers.Signer | ethers.Provider) {
    const provider = signerOrProvider || getProvider();
    if (!provider) return null;
    return new ethers.Contract(assetManagerConfig.address, assetManagerConfig.abi, provider);
}

export function getERC20Contract(
    tokenAddress: string,
    signerOrProvider?: ethers.Signer | ethers.Provider
) {
    const provider = signerOrProvider || getProvider();
    if (!provider) return null;
    return new ethers.Contract(
        tokenAddress,
        ERC20_ABI, // Use explicitly defined ABI
        provider
    );
}
