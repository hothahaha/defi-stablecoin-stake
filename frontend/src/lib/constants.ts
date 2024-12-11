import { useEffect, useState } from "react";
import { getAssetManagerContract, getSigner } from "./contract-utils";

export function useSupportedAssets() {
    const [supportedAssets, setSupportedAssets] = useState<`0x${string}`[]>([]);

    useEffect(() => {
        async function fetchSupportedAssets() {
            const signer = await getSigner();
            if (!signer) return;

            const contract = getAssetManagerContract(signer);
            if (!contract) return;

            try {
                const assets = await contract.getSupportedAssets();
                setSupportedAssets(assets);
            } catch (error) {
                console.error("Failed to fetch supported assets:", error);
            }
        }

        fetchSupportedAssets();
    }, []);

    return supportedAssets;
}
