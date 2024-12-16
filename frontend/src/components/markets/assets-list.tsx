"use client";

import { useState, useEffect } from "react";
import { AssetCard } from "./asset-card";
import { SupplyModal } from "./supply-modal";
import { BorrowModal } from "./borrow-modal";
import { useAssets } from "@/hooks/use-assets";
import { Asset } from "@/types";
import { useAccount } from "wagmi";

interface AssetsListProps {
    onSuccess?: () => void;
}

export function AssetsList({ onSuccess }: AssetsListProps) {
    const { isConnected } = useAccount();
    const { assets, refetch } = useAssets();
    const [selectedAsset, setSelectedAsset] = useState<Asset | null>(null);
    const [isSupplyModalOpen, setIsSupplyModalOpen] = useState(false);
    const [isBorrowModalOpen, setIsBorrowModalOpen] = useState(false);
    const [refreshKey, setRefreshKey] = useState(0);

    useEffect(() => {
        if (isConnected) {
            refetch();
        }
    }, [isConnected, refetch]);

    const handleSuccess = async () => {
        await refetch();
        setRefreshKey((prev) => prev + 1);
        onSuccess?.();
    };

    return (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            <div className="rounded-lg border p-6">
                <h2 className="text-lg font-semibold mb-4">Deposit Market</h2>
                <div className="space-y-4">
                    {assets.map((asset) => (
                        <AssetCard
                            key={`supply-${asset.token}`}
                            asset={asset}
                            type="supply"
                            onSupply={() => {
                                setSelectedAsset(asset);
                                setIsSupplyModalOpen(true);
                            }}
                            refreshKey={refreshKey}
                        />
                    ))}
                </div>
            </div>

            <div className="rounded-lg border p-6">
                <h2 className="text-lg font-semibold mb-4">Borrow Market</h2>
                <div className="space-y-4">
                    {assets.map((asset) => (
                        <AssetCard
                            key={`borrow-${asset.token}`}
                            asset={asset}
                            type="borrow"
                            onBorrow={() => {
                                setSelectedAsset(asset);
                                setIsBorrowModalOpen(true);
                            }}
                            refreshKey={refreshKey}
                        />
                    ))}
                </div>
            </div>

            {selectedAsset && (
                <>
                    <SupplyModal
                        isOpen={isSupplyModalOpen}
                        onClose={() => setIsSupplyModalOpen(false)}
                        asset={selectedAsset}
                        onSuccess={handleSuccess}
                    />
                    <BorrowModal
                        isOpen={isBorrowModalOpen}
                        onClose={() => setIsBorrowModalOpen(false)}
                        asset={selectedAsset}
                        onSuccess={handleSuccess}
                    />
                </>
            )}
        </div>
    );
}
