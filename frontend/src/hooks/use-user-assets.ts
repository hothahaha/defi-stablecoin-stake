import { useEffect, useState } from "react";
import { useAccount } from "wagmi";
import { useSupportedAssets } from "@/lib/constants";
import { getLendingPoolContract, getSigner } from "@/lib/contract-utils";
import { Asset, UserAsset } from "@/types";
import { useAssets } from "./use-assets";

interface UserAssetsInfo {
    deposits: UserAsset[];
    borrows: UserAsset[];
    totalDepositValue: bigint;
    totalBorrowValue: bigint;
    refetch: () => Promise<void>;
}

export function useUserAssets(): UserAssetsInfo {
    const supportedAssets = useSupportedAssets();
    const { address } = useAccount();
    const assets = useAssets();
    const [userAssets, setUserAssets] = useState<UserAsset[]>([]);
    const [totalValues, setTotalValues] = useState<[bigint, bigint]>([0n, 0n]);

    const fetchUserAssets = async () => {
        if (!address) return;
        const signer = await getSigner();
        if (!signer) return;

        const contract = getLendingPoolContract(signer);
        if (!contract) return;

        try {
            // 获取用户总价值
            const [totalDepositValue, totalBorrowValue] = await contract.getUserTotalValueInUSD(
                address
            );

            // 获取每个资产的用户信息
            const userAssetsPromises = supportedAssets.map(async (token) => {
                const asset = assets.find((a) => a.token === token);
                if (!asset) return null;

                try {
                    const userInfo = await contract.getUserInfo(token, address);
                    return {
                        token,
                        symbol: asset.config.symbol,
                        name: asset.config.name,
                        decimals: asset.config.decimals,
                        icon: asset.config.icon,
                        depositAmount: userInfo.depositAmount,
                        borrowAmount: userInfo.borrowAmount,
                        config: asset.config,
                    };
                } catch (error) {
                    console.error(`Failed to fetch user info for token ${token}:`, error);
                    return null;
                }
            });

            const processedAssets = (await Promise.all(userAssetsPromises)).filter(Boolean);
            setUserAssets(processedAssets);
            setTotalValues([totalDepositValue, totalBorrowValue]);
        } catch (error) {
            console.error("Failed to fetch user assets:", error);
        }
    };

    useEffect(() => {
        fetchUserAssets();
    }, [address, assets, supportedAssets]);

    const deposits = userAssets.filter((asset) => asset.depositAmount > 0n);
    const borrows = userAssets.filter((asset) => asset.borrowAmount > 0n);

    return {
        deposits,
        borrows,
        totalDepositValue: totalValues[0],
        totalBorrowValue: totalValues[1],
        refetch: fetchUserAssets,
    };
}
