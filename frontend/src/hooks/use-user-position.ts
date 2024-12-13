import { useState, useEffect } from "react";
import { formatUnits, parseUnits } from "ethers";
import { getLendingPoolContract, getSigner } from "@/lib/contract-utils";
import { COLLATERAL_TOKEN_ADDRESS } from "@/lib/contract-config";
import { useAssetPrice } from "./use-asset-price";

export function useUserPosition(address?: string) {
    const [userInfo, setUserInfo] = useState<{
        depositAmount: bigint;
        borrowAmount: bigint;
        healthFactor: bigint;
        lastUpdateTime: bigint;
    }>({
        depositAmount: 0n,
        borrowAmount: 0n,
        healthFactor: 0n,
        lastUpdateTime: 0n,
    });

    const { price: collateralPrice } = useAssetPrice(COLLATERAL_TOKEN_ADDRESS);

    useEffect(() => {
        async function fetchUserInfo() {
            if (!address) return;
            const signer = await getSigner();
            if (!signer) return;

            const contract = getLendingPoolContract(signer);
            if (!contract) return;

            try {
                const info = await contract.getUserInfo(address);
                setUserInfo({
                    depositAmount: info[0],
                    borrowAmount: info[1],
                    healthFactor: info[2],
                    lastUpdateTime: info[3],
                });
            } catch (error) {
                console.error("Failed to fetch user info:", error);
            }
        }

        fetchUserInfo();
    }, [address]);

    return {
        ...userInfo,
        depositValue: formatUnits(
            userInfo.depositAmount * BigInt(parseUnits(collateralPrice?.toString() ?? "0", 18)),
            36
        ),
        borrowValue: formatUnits(
            userInfo.borrowAmount * BigInt(parseUnits(collateralPrice?.toString() ?? "0", 18)),
            36
        ),
    };
}
