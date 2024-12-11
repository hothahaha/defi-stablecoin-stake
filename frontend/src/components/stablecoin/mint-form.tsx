import { useState } from "react";
import { useWriteContract, useSimulateContract } from "wagmi";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { stablecoinConfig } from "@/lib/contract-config";
import { parseUnits } from "viem";

export function MintStablecoinForm() {
  const [collateral, setCollateral] = useState("");
  const [amount, setAmount] = useState("");

  const { data: simulateData } = useSimulateContract({
    address: stablecoinConfig.address as `0x${string}`,
    abi: stablecoinConfig.abi,
    functionName: 'mint',
    args: [parseUnits(amount || "0", 18)],
  });

  const { writeContract, isPending } = useWriteContract();

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!simulateData?.request) return;
    writeContract(simulateData.request);
  };

  return (
    <div className="rounded-lg border p-4">
      <h2 className="text-lg font-medium">铸造稳定币</h2>
      
      <form onSubmit={handleSubmit} className="mt-4 space-y-4">
        <div>
          <Label>抵押品数量</Label>
          <Input 
            type="number" 
            value={collateral}
            onChange={(e) => setCollateral(e.target.value)}
          />
        </div>

        <div>
          <Label>铸造数量</Label>
          <Input 
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </div>

        <Button type="submit" className="w-full" disabled={isPending}>
          {isPending ? "处理中..." : "铸造"}
        </Button>
      </form>
    </div>
  );
} 