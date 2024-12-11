"use client";

import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { useWriteContract, useSimulateContract, useBalance } from "wagmi";
import { stablecoinConfig } from "@/lib/contract-config";
import { parseUnits } from "viem";

export function StablecoinBurn() {
    const [amount, setAmount] = useState("");

    const { data: stablecoinBalance } = useBalance({
        address: stablecoinConfig.address as `0x${string}`,
        token: stablecoinConfig.address as `0x${string}`,
    });

    const { data: simulateData } = useSimulateContract({
        address: stablecoinConfig.address as `0x${string}`,
        abi: stablecoinConfig.abi,
        functionName: "burn",
        args: [parseUnits(amount || "0", 18)],
    });

    const { writeContract, isPending } = useWriteContract();

    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        if (!amount || !simulateData?.request) return;

        try {
            writeContract(simulateData.request);
        } catch (error) {
            console.error("Error burning stablecoin:", error);
        }
    };

    return (
        <Card>
            <CardHeader>
                <CardTitle>销毁稳定币</CardTitle>
            </CardHeader>
            <CardContent>
                <form
                    onSubmit={handleSubmit}
                    className="space-y-4"
                >
                    <div>
                        <Label>销毁数量</Label>
                        <div className="flex items-center gap-2">
                            <Input
                                type="number"
                                value={amount}
                                onChange={(e) => setAmount(e.target.value)}
                                placeholder="输入销毁数量"
                            />
                            <div className="text-sm text-muted-foreground">
                                可用: {stablecoinBalance?.formatted ?? "0"}{" "}
                                {stablecoinBalance?.symbol}
                            </div>
                        </div>
                    </div>

                    <Button
                        type="submit"
                        className="w-full"
                        disabled={isPending}
                    >
                        {isPending ? "处理中..." : "销毁"}
                    </Button>
                </form>
            </CardContent>
        </Card>
    );
}
