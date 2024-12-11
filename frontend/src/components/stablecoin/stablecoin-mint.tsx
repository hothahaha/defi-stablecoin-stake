"use client";

import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select";
import { useAccount, useBalance, useWriteContract, useSimulateContract } from "wagmi";
import { COLLATERAL_TOKEN_ADDRESS, stablecoinConfig } from "@/lib/contract-config";
import { parseUnits } from "viem";

export function StablecoinMint() {
    const [collateralAmount, setCollateralAmount] = useState("");
    const [leverage, setLeverage] = useState("1");

    const { address } = useAccount();
    const { data: collateralBalance } = useBalance({
        address,
        token: COLLATERAL_TOKEN_ADDRESS as `0x${string}`,
    });

    const { data: simulateData } = useSimulateContract({
        address: stablecoinConfig.address as `0x${string}`,
        abi: stablecoinConfig.abi,
        functionName: "mint",
        args: [parseUnits(collateralAmount || "0", 18), Number(leverage)],
    });

    const { writeContract, isPending } = useWriteContract();

    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        if (!collateralAmount || !simulateData?.request) return;

        try {
            writeContract(simulateData.request);
        } catch (error) {
            console.error("Error minting stablecoin:", error);
        }
    };

    return (
        <Card>
            <CardHeader>
                <CardTitle>铸造稳定币</CardTitle>
                <CardDescription>质押资产铸造稳定币,支持多种杠杆倍率</CardDescription>
            </CardHeader>
            <CardContent>
                <form
                    onSubmit={handleSubmit}
                    className="space-y-4"
                >
                    <div>
                        <Label>质押数量</Label>
                        <div className="flex items-center gap-2">
                            <Input
                                type="number"
                                value={collateralAmount}
                                onChange={(e) => setCollateralAmount(e.target.value)}
                                placeholder="输入质押数量"
                            />
                            <div className="text-sm text-muted-foreground">
                                可用: {collateralBalance?.formatted ?? "0"}{" "}
                                {collateralBalance?.symbol}
                            </div>
                        </div>
                    </div>

                    <div>
                        <Label>杠杆倍率</Label>
                        <Select
                            value={leverage}
                            onValueChange={setLeverage}
                        >
                            <SelectTrigger>
                                <SelectValue placeholder="选择杠杆倍率" />
                            </SelectTrigger>
                            <SelectContent>
                                <SelectItem value="1">1x</SelectItem>
                                <SelectItem value="2">2x</SelectItem>
                                <SelectItem value="3">3x</SelectItem>
                            </SelectContent>
                        </Select>
                    </div>

                    <Button
                        type="submit"
                        className="w-full"
                        disabled={isPending}
                    >
                        {isPending ? "处理中..." : "铸造稳定币"}
                    </Button>
                </form>
            </CardContent>
        </Card>
    );
}
