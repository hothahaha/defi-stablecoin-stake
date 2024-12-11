"use client";

import { useState } from "react";
import { useUserAssets } from "@/hooks/use-user-assets";
import { UserAssetCard } from "./user-asset-card";
import { WithdrawModal } from "./withdraw-modal";
import { RepayModal } from "./repay-modal";
import { Asset, UserAsset } from "@/types";

export function UserAssetsList({ onSuccess }: { onSuccess?: () => void }) {
    const [selectedAsset, setSelectedAsset] = useState<UserAsset | null>(null);
    const [isWithdrawModalOpen, setIsWithdrawModalOpen] = useState(false);
    const [isRepayModalOpen, setIsRepayModalOpen] = useState(false);
    const [refreshKey, setRefreshKey] = useState(0);
    const { deposits, borrows, refetch } = useUserAssets();

    const handleSuccess = async () => {
        await refetch();
        setRefreshKey((prev) => prev + 1);
        onSuccess?.();
    };

    return (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            <div className="rounded-lg border p-6">
                <h2 className="text-lg font-semibold mb-4">My Deposit</h2>
                <div className="space-y-4">
                    {deposits.map((asset) => (
                        <UserAssetCard
                            key={`deposit-${asset.token}`}
                            asset={asset}
                            type="deposit"
                            onWithdraw={() => {
                                setSelectedAsset(asset);
                                setIsWithdrawModalOpen(true);
                            }}
                            refreshKey={refreshKey}
                        />
                    ))}
                    {deposits.length === 0 && (
                        <p className="text-sm text-muted-foreground text-center py-4">
                            No deposit assets yet
                        </p>
                    )}
                </div>
            </div>

            <div className="rounded-lg border p-6">
                <h2 className="text-lg font-semibold mb-4">My Borrow</h2>
                <div className="space-y-4">
                    {borrows.map((asset) => (
                        <UserAssetCard
                            key={`borrow-${asset.token}`}
                            asset={asset}
                            type="borrow"
                            onRepay={() => {
                                setSelectedAsset(asset);
                                setIsRepayModalOpen(true);
                            }}
                            refreshKey={refreshKey}
                        />
                    ))}
                    {borrows.length === 0 && (
                        <p className="text-sm text-muted-foreground text-center py-4">
                            No borrow assets yet
                        </p>
                    )}
                </div>
            </div>

            {selectedAsset && (
                <>
                    <WithdrawModal
                        isOpen={isWithdrawModalOpen}
                        onClose={() => setIsWithdrawModalOpen(false)}
                        asset={selectedAsset}
                        onSuccess={handleSuccess}
                    />
                    <RepayModal
                        isOpen={isRepayModalOpen}
                        onClose={() => setIsRepayModalOpen(false)}
                        asset={selectedAsset}
                        onSuccess={handleSuccess}
                    />
                </>
            )}
        </div>
    );
}
