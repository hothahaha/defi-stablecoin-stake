import { useEffect, useState } from "react";
import { useSupportedAssets } from "@/lib/constants";
import { getLendingPoolContract, getAssetManagerContract, getSigner } from "@/lib/contract-utils";
import { Asset } from "@/types";

export function useAssets(): Asset[] {
    const supportedAssets = useSupportedAssets();
    const [assets, setAssets] = useState<Asset[]>([]);

    useEffect(() => {
        async function fetchAssets() {
            const signer = await getSigner();
            if (!signer) return;

            const lendingPool = getLendingPoolContract(signer);
            const assetManager = getAssetManagerContract(signer);
            if (!lendingPool || !assetManager) return;

            try {
                // Fetch asset data in parallel
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
                console.error("Failed to fetch assets:", error);
                return [];
            }
        }

        fetchAssets();
    }, [supportedAssets]);

    return assets;
}
