"use client";

import { useState } from "react";
import { MarketStats } from "@/components/markets/market-stats";
import { AssetsList } from "@/components/markets/assets-list";

export default function MarketsPage() {
    const [refreshKey, setRefreshKey] = useState(0);

    const handleSuccess = () => {
        setRefreshKey((prev) => prev + 1);
    };

    return (
        <div className="container py-6">
            <h1 className="text-2xl font-bold mb-6">Market Preview</h1>

            <div className="grid gap-6">
                <MarketStats key={`stats-${refreshKey}`} />
                <AssetsList
                    key={`assets-${refreshKey}`}
                    onSuccess={handleSuccess}
                />
            </div>
        </div>
    );
}
