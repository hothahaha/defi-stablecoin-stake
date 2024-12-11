import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";
import { formatUnits, parseUnits } from "viem";

export function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

export function formatAmount(amount: bigint, decimals: number = 18): string {
    return formatUnits(amount, decimals);
}

export function parseAmount(amount: string, decimals: number = 18): bigint {
    try {
        return parseUnits(amount, decimals);
    } catch {
        return 0n;
    }
}

export function shortenAddress(address: string): string {
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function calculateHealthFactor(
    collateralValue: bigint,
    borrowValue: bigint,
    collateralFactor: bigint
): string {
    if (borrowValue === 0n) return "∞";

    const healthFactor = (collateralValue * collateralFactor * 100n) / (borrowValue * 10000n);
    return formatUnits(healthFactor, 18);
}

export function formatNumber(value: string | number, decimals = 2): string {
    const num = Number(value);
    return new Intl.NumberFormat("en-US", {
        minimumFractionDigits: decimals,
        maximumFractionDigits: decimals,
    }).format(num);
}
