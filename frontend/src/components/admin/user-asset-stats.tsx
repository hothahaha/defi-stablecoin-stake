"use client";

import { StatCard } from "@/components/ui/stat-card";
import { useUserAssets } from "@/hooks/use-user-assets";
import { formatUnits } from "ethers";
import { useEffect } from "react";

interface UserAssetStatsProps {
    refreshKey?: number;
}

export function UserAssetStats({ refreshKey = 0 }: UserAssetStatsProps) {
    const { totalDepositValue, totalBorrowValue } = useUserAssets();

    return (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <StatCard
                title="Total Deposit Value"
                value={`$${Number(formatUnits(totalDepositValue, 18)).toLocaleString()}`}
            />
            <StatCard
                title="Total Borrow Value"
                value={`$${Number(formatUnits(totalBorrowValue, 18)).toLocaleString()}`}
            />
        </div>
    );
}
