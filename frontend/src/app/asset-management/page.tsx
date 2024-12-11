"use client";

import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { formatUnits } from "ethers";
import { AddAssetModal } from "@/components/asset-management/add-asset-modal";
import { UpdateAssetModal } from "@/components/asset-management/update-asset-modal";
import { Asset } from "@/types";
import { useAssets } from "@/hooks/use-assets";
import { getLendingPoolContract, getSigner } from "@/lib/contract-utils";

export default function AssetManagementPage() {
    const assets = useAssets();
    const [selectedAsset, setSelectedAsset] = useState<Asset | null>(null);
    const [isAddModalOpen, setIsAddModalOpen] = useState(false);
    const [isUpdateModalOpen, setIsUpdateModalOpen] = useState(false);
    const [assetValues, setAssetValues] = useState<{ [key: string]: [bigint, bigint] }>({});
    const [refreshKey, setRefreshKey] = useState(0);

    // Fetch USD values for each asset
    useEffect(() => {
        async function fetchAssetValues() {
            const signer = await getSigner();
            if (!signer) return;

            const contract = getLendingPoolContract(signer);
            if (!contract) return;

            try {
                const valuePromises = assets.flatMap(async (asset) => {
                    const [depositValue, borrowValue] = await Promise.all([
                        contract.getValueUsdByAmount(asset.token, asset.info.totalDeposits),
                        contract.getValueUsdByAmount(asset.token, asset.info.totalBorrows),
                    ]);
                    return [asset.token, [depositValue, borrowValue]];
                });

                const values = await Promise.all(valuePromises);
                const valuesMap = Object.fromEntries(values);
                setAssetValues(valuesMap);
            } catch (error) {
                console.error("Failed to fetch asset values:", error);
            }
        }

        if (assets.length > 0) {
            fetchAssetValues();
        }
    }, [assets, refreshKey]);

    const handleRefresh = () => {
        setRefreshKey((prev) => prev + 1);
    };

    return (
        <div className="container py-8">
            <div className="flex justify-between items-center mb-6">
                <h1 className="text-2xl font-bold">Asset Management</h1>
                <Button onClick={() => setIsAddModalOpen(true)}>Add Asset</Button>
            </div>

            <div className="grid gap-4">
                {assets.map((asset) => {
                    const [depositValueUsd, borrowValueUsd] = assetValues[asset.token] ?? [0n, 0n];
                    const collateralFactorPercent = Number(
                        formatUnits(asset.config.collateralFactor, 16)
                    );
                    const borrowFactorPercent = Number(formatUnits(asset.config.borrowFactor, 16));

                    return (
                        <Card key={asset.token}>
                            <CardContent className="flex items-center justify-between p-4">
                                <div className="flex items-center gap-3">
                                    <img
                                        src={asset.config.icon}
                                        alt={asset.config.symbol}
                                        className="w-8 h-8"
                                    />
                                    <div>
                                        <h3 className="font-medium">{asset.config.symbol}</h3>
                                        <div className="text-sm text-muted-foreground space-y-1">
                                            <p>Collateral Factor: {collateralFactorPercent.toFixed(0)}%</p>
                                            <p>Borrow Factor: {borrowFactorPercent.toFixed(0)}%</p>
                                        </div>
                                    </div>
                                </div>

                                <div className="text-sm text-right">
                                    <p>
                                        Total Deposits: $
                                        {Number(formatUnits(depositValueUsd, 18)).toLocaleString()}
                                    </p>
                                    <p>
                                        Total Borrows: $
                                        {Number(formatUnits(borrowValueUsd, 18)).toLocaleString()}
                                    </p>
                                </div>

                                <Button
                                    variant="outline"
                                    onClick={() => {
                                        setSelectedAsset(asset);
                                        setIsUpdateModalOpen(true);
                                    }}
                                >
                                    Update
                                </Button>
                            </CardContent>
                        </Card>
                    );
                })}
            </div>

            <AddAssetModal
                isOpen={isAddModalOpen}
                onClose={() => setIsAddModalOpen(false)}
                onSuccess={handleRefresh}
            />

            {selectedAsset && (
                <UpdateAssetModal
                    isOpen={isUpdateModalOpen}
                    onClose={() => setIsUpdateModalOpen(false)}
                    asset={selectedAsset}
                    onSuccess={handleRefresh}
                />
            )}
        </div>
    );
}
