"use client";

import { useAccount, useReadContract } from "wagmi";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { getLendingPoolContract, getSigner } from "@/lib/contract-utils";
import { formatUnits } from "ethers";
import { lendingPoolConfig } from "@/lib/contract-config";
import { useState } from "react";

export function RewardsCard({ onSuccess }: { onSuccess?: () => void }) {
    const { address } = useAccount();
    const [isWaitingTx, setIsWaitingTx] = useState(false);

    const { data: rewardDebt, refetch } = useReadContract({
        address: lendingPoolConfig.address,
        abi: lendingPoolConfig.abi,
        functionName: "getUserRewardDebt",
        args: [address],
    });

    const rewards = rewardDebt ? formatUnits(rewardDebt, 18) : "0";

    const handleClaimRewards = async () => {
        if (!address) return;
        try {
            setIsWaitingTx(true);
            const signer = await getSigner();
            if (!signer) throw new Error("No signer");

            const contract = getLendingPoolContract(signer);
            if (!contract) throw new Error("No contract");

            const tx = await contract.claimReward(signer);
            await tx.wait();
            await refetch();
            onSuccess?.();
        } catch (error) {
            console.error("Claim rewards failed:", error);
        } finally {
            setIsWaitingTx(false);
        }
    };

    return (
        <Card>
            <CardHeader>
                <CardTitle>Rewards</CardTitle>
                <CardDescription>Deposit and borrow can get platform token rewards</CardDescription>
            </CardHeader>
            <CardContent>
                <div className="flex items-center justify-between">
                    <div>
                        <p className="text-sm text-muted-foreground">Rewards available</p>
                        <p className="text-2xl font-bold">{Number(rewards).toFixed(4)}</p>
                    </div>

                    <Button
                        onClick={handleClaimRewards}
                        disabled={Number(rewards) === 0 || isWaitingTx}
                    >
                        {isWaitingTx ? "Processing..." : "Claim Rewards"}
                    </Button>
                </div>
            </CardContent>
        </Card>
    );
}
