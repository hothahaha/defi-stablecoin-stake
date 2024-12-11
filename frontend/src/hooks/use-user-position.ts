import { useReadContract } from "wagmi";
import { formatUnits, parseUnits } from "viem";
import { lendingPoolConfig } from "@/lib/contract-config";
import { COLLATERAL_TOKEN_ADDRESS } from "@/lib/constants";
import { useAssetPrice } from "./use-asset-price";

type UserInfo = readonly [
    depositAmount: bigint,
    borrowAmount: bigint,
    healthFactor: bigint,
    lastUpdateTime: bigint
];

export function useUserPosition(address?: string) {
    const { data: userInfo } = useReadContract<
        typeof lendingPoolConfig.abi,
        "getUserInfo",
        UserInfo
    >({
        address: lendingPoolConfig.address,
        abi: lendingPoolConfig.abi,
        functionName: "getUserInfo",
        args: address ? [address as `0x${string}`] : undefined,
    });

    const { price: collateralPrice } = useAssetPrice(COLLATERAL_TOKEN_ADDRESS);

    if (!userInfo) {
        return {
            depositAmount: 0n,
            borrowAmount: 0n,
            healthFactor: 0n,
            lastUpdateTime: 0n,
            depositValue: "0",
            borrowValue: "0",
        };
    }

    return {
        depositAmount: userInfo[0],
        borrowAmount: userInfo[1],
        healthFactor: userInfo[2],
        lastUpdateTime: userInfo[3],
        depositValue: formatUnits(
            userInfo[0] * BigInt(parseUnits(collateralPrice?.toString() ?? "0", 18)),
            36
        ),
        borrowValue: formatUnits(
            userInfo[1] * BigInt(parseUnits(collateralPrice?.toString() ?? "0", 18)),
            36
        ),
    };
}
