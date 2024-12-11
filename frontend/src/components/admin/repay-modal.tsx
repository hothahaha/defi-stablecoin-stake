import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { useAccount } from "wagmi";
import { UserAsset } from "@/types";
import { parseUnits, formatUnits } from "ethers";
import { getLendingPoolContract, getERC20Contract, getSigner } from "@/lib/contract-utils";

export function RepayModal({
    isOpen,
    onClose,
    asset,
    onSuccess,
}: {
    isOpen: boolean;
    onClose: () => void;
    asset: UserAsset;
    onSuccess?: () => void;
}) {
    const [amount, setAmount] = useState("");
    const [isWaitingTx, setIsWaitingTx] = useState(false);
    const { address } = useAccount();

    useEffect(() => {
        if (!isOpen) {
            setAmount("");
            setIsWaitingTx(false);
        }
    }, [isOpen]);

    const parsedAmount = amount ? parseUnits(amount, asset.decimals) : 0n;
    const formattedBorrowAmount = formatUnits(asset.borrowAmount || 0n, asset.decimals);

    const handleRepay = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!amount || !address) return;

        try {
            setIsWaitingTx(true);
            const signer = await getSigner();
            if (!signer) throw new Error("No signer");

            const contract = getLendingPoolContract(signer);
            if (!contract) throw new Error("No contract");

            const tx = await contract.repay(asset.token, parsedAmount, {
                gasLimit: 500000n,
            });

            await tx.wait();
            onSuccess?.();
            onClose();
        } catch (error) {
            console.error("Repay failed:", error);
            alert(error.message || "Repay failed");
        } finally {
            setIsWaitingTx(false);
        }
    };

    return (
        <Dialog
            open={isOpen}
            onOpenChange={onClose}
        >
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Repay {asset.symbol}</DialogTitle>
                </DialogHeader>

                <form
                    onSubmit={handleRepay}
                    className="space-y-4"
                >
                    <div>
                        <Label>Repay Amount</Label>
                        <div className="flex items-center gap-2">
                            <Input
                                type="number"
                                value={amount}
                                onChange={(e) => setAmount(e.target.value)}
                                placeholder="Enter repay amount"
                            />
                            <Button
                                type="button"
                                variant="outline"
                                onClick={() => setAmount(formattedBorrowAmount)}
                            >
                                All
                            </Button>
                        </div>
                        <div className="text-sm text-muted-foreground mt-1">
                            Repay Amount: {formattedBorrowAmount} {asset.symbol}
                        </div>
                    </div>

                    <Button
                        type="submit"
                        className="w-full"
                        disabled={isWaitingTx}
                    >
                        {isWaitingTx ? "Processing..." : "Confirm Repay"}
                    </Button>
                </form>
            </DialogContent>
        </Dialog>
    );
}
