"use client";

import { useEffect, useState } from "react";
import { StatCard } from "@/components/ui/stat-card";
import { getLendingPoolContract, getSigner } from "@/lib/contract-utils";
import { formatUnits } from "ethers";
import { useAccount } from "wagmi";

interface MarketStatsProps {
    refreshKey?: number;
}

export function MarketStats({ refreshKey = 0 }: MarketStatsProps) {
    const { isConnected } = useAccount();
    const [totalValues, setTotalValues] = useState<[bigint, bigint]>([0n, 0n]);

    const fetchTotalValues = async () => {
        if (!isConnected) return;

        const signer = await getSigner();
        if (!signer) return;

        const contract = getLendingPoolContract(signer);
        if (!contract) return;

        try {
            const [deposits, borrows] = await contract.getTotalValues();
            setTotalValues([deposits, borrows]);
        } catch (error) {
            console.warn("Failed to fetch total values:", error);
        }
    };

    // 监听钱包连接状态和刷新键
    useEffect(() => {
        fetchTotalValues();
    }, [refreshKey, isConnected]);

    const [totalDeposits, totalBorrows] = totalValues;

    return (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <StatCard
                title="Total Deposits"
                value={`$${Number(formatUnits(totalDeposits, 18)).toLocaleString()}`}
            />
            <StatCard
                title="Total Borrows"
                value={`$${Number(formatUnits(totalBorrows, 18)).toLocaleString()}`}
            />
            <StatCard
                title="Total Liquidity"
                value={`$${(
                    Number(formatUnits(totalDeposits, 18)) - Number(formatUnits(totalBorrows, 18))
                ).toLocaleString()}`}
            />
        </div>
    );
}
