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
        throw new Error("No wallet found");
    }
    return new ethers.BrowserProvider(window.ethereum);
}

export async function getSigner() {
    const provider = getProvider();
    if (!provider) return null;
    const signer = await provider.getSigner();
    if (!signer) {
        throw new Error("Failed to get signer");
    }
    return signer;
}

export function getLendingPoolContract(signerOrProvider?: ethers.Signer | ethers.Provider) {
    const provider = signerOrProvider || getProvider();
    if (!provider) return null;
    return new ethers.Contract(
        lendingPoolConfig.address,
        lendingPoolConfig.abi, // Use explicitly defined ABI
        provider
    );
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
