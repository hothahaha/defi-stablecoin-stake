import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { UserAsset } from "@/types";
import { formatUnits } from "ethers";

interface UserAssetCardProps {
    asset: UserAsset;
    type: "deposit" | "borrow";
    onWithdraw?: () => void;
    onRepay?: () => void;
    refreshKey?: number;
}

export function UserAssetCard({ asset, type, onWithdraw, onRepay, refreshKey = 0 }: UserAssetCardProps) {
    const amount = type === "deposit" ? asset.depositAmount : asset.borrowAmount;
    const formattedAmount = formatUnits(amount || 0n, asset.decimals);

    return (
        <Card className="p-6">
            <div className="flex justify-between items-center">
                <div className="flex items-center gap-3">
                    <img
                        src={asset.icon}
                        alt={asset.name}
                        className="w-8 h-8"
                    />
                    <div>
                        <h3 className="font-medium">{asset.name}</h3>
                        <p className="text-sm text-muted-foreground">
                            {type === "deposit"
                                ? `Deposit Amount: ${formattedAmount}`
                                : `Borrow Amount: ${formattedAmount}`}{" "}
                            {asset.symbol}
                        </p>
                    </div>
                </div>
                <Button onClick={type === "deposit" ? onWithdraw : onRepay}>
                    {type === "deposit" ? "Withdraw" : "Repay"}
                </Button>
            </div>
        </Card>
    );
}
