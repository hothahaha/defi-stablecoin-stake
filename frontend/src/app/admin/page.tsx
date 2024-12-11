"use client";

import { useState } from "react";
import { UserAssetStats } from "@/components/admin/user-asset-stats";
import { UserAssetsList } from "@/components/admin/user-assets-list";
import { RewardsCard } from "@/components/admin/rewards-card";

export default function AdminPage() {
    const [refreshKey, setRefreshKey] = useState(0);

    const handleSuccess = () => {
        setRefreshKey((prev) => prev + 1);
    };

    return (
        <div className="container py-6">
            <h1 className="text-2xl font-bold mb-6">My Asset</h1>

            <div className="grid gap-6">
                <UserAssetStats key={`stats-${refreshKey}`} />
                <UserAssetsList key={`assets-${refreshKey}`} />
                <RewardsCard key={`rewards-${refreshKey}`} />
            </div>
        </div>
    );
}
