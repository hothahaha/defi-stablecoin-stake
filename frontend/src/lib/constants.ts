import { useEffect, useState } from "react";
import { getAssetManagerContract, getSigner } from "./contract-utils";
import { useAccount } from "wagmi";

export function useSupportedAssets() {
    const [supportedAssets, setSupportedAssets] = useState<`0x${string}`[]>([]);
    const { isConnected } = useAccount();

    useEffect(() => {
        async function fetchSupportedAssets() {
            if (!isConnected) return;

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
    }, [isConnected]);

    return supportedAssets;
}
