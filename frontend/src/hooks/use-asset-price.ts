import { useEffect, useState } from "react";
import { formatUnits } from "ethers";
import { getLendingPoolContract, getSigner } from "@/lib/contract-utils";

export function useAssetPrice(tokenAddress: string) {
    const [price, setPrice] = useState("0");

    useEffect(() => {
        async function fetchPrice() {
            const signer = await getSigner();
            if (!signer) return;

            const contract = getLendingPoolContract(signer);
            if (!contract) return;

            try {
                const priceResult = await contract.getAssetPrice(tokenAddress);
                setPrice(formatUnits(priceResult, 8));
            } catch (error) {
                console.error("Failed to fetch price:", error);
            }
        }

        fetchPrice();
    }, [tokenAddress]);

    return { price };
}
