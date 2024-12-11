import { useEffect, useState } from "react";
import { Asset } from "@/types";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { getLendingPoolContract, getSigner } from "@/lib/contract-utils";
import { formatUnits } from "ethers";

interface AssetCardProps {
    asset: Asset;
    type: "supply" | "borrow";
    onSupply?: () => void;
    onBorrow?: () => void;
    refreshKey?: number;
}

export function AssetCard({ asset, type, onSupply, onBorrow, refreshKey = 0 }: AssetCardProps) {
    const [rates, setRates] = useState<{ depositRate: bigint; borrowRate: bigint }>({
        depositRate: 0n,
        borrowRate: 0n,
    });

    const fetchRates = async () => {
        const signer = await getSigner();
        if (!signer) return;

        const contract = getLendingPoolContract(signer);
        if (!contract) return;

        try {
            const assetInfo = await contract.getAssetInfo(asset.token);
            setRates({
                depositRate: assetInfo.depositRate,
                borrowRate: assetInfo.borrowRate,
            });
        } catch (error) {
            console.error("Failed to fetch rates:", error);
        }
    };

    useEffect(() => {
        fetchRates();
    }, [asset.token, refreshKey]);

    return (
        <Card>
            <CardContent className="p-4">
                <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                        <img
                            src={asset.config.icon}
                            alt={asset.config.symbol}
                            className="w-8 h-8"
                        />
                        <div>
                            <h3 className="font-medium">{asset.config.name}</h3>
                            <p className="text-sm text-muted-foreground">{asset.config.symbol}</p>
                        </div>
                    </div>

                    <div className="text-right">
                        ${Number(formatUnits(asset.price, 8)).toFixed(2)}
                        <p className="text-sm text-muted-foreground">
                            {type === "supply"
                                ? `Supply APY: ${Number(formatUnits(rates.depositRate, 16)).toFixed(
                                      2
                                  )}%`
                                : `Borrow APY: ${Number(formatUnits(rates.borrowRate, 16)).toFixed(
                                      2
                                  )}%`}
                        </p>
                    </div>
                </div>

                <div className="mt-4">
                    {type === "supply" ? (
                        <Button
                            onClick={onSupply}
                            className="w-full"
                        >
                            Supply
                        </Button>
                    ) : (
                        <Button
                            onClick={onBorrow}
                            className="w-full"
                        >
                            Borrow
                        </Button>
                    )}
                </div>
            </CardContent>
        </Card>
    );
}
