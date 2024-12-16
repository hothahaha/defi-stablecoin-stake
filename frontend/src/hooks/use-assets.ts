import { useEffect, useState } from "react";
import { useSupportedAssets } from "@/lib/constants";
import { getLendingPoolContract, getAssetManagerContract, getSigner } from "@/lib/contract-utils";
import { Asset } from "@/types";
import { useAccount } from "wagmi";

export function useAssets() {
    const supportedAssets = useSupportedAssets();
    const [assets, setAssets] = useState<Asset[]>([]);
    const { isConnected } = useAccount();

    const fetchAssets = async () => {
        if (!isConnected) return;
        
        const signer = await getSigner();
        if (!signer) return;

        const lendingPool = getLendingPoolContract(signer);
        const assetManager = getAssetManagerContract(signer);
        if (!lendingPool || !assetManager) return;

        try {
            const assetPromises = supportedAssets.map(async (token) => {
                const [price, config, info] = await Promise.all([
                    lendingPool.getAssetPrice(token),
                    assetManager.getAssetConfig(token),
                    lendingPool.getAssetInfo(token),
                ]);

                return {
                    token,
                    price,
                    config,
                    info,
                };
            });

            const results = await Promise.all(assetPromises);
            setAssets(results);
        } catch (error) {
            console.warn("Failed to fetch assets:", error);
        }
    };

    // 监听钱包连接状态和支持的资产变化
    useEffect(() => {
        fetchAssets();
    }, [isConnected, supportedAssets]);

    return {
        assets,
        refetch: fetchAssets,
    };
}
