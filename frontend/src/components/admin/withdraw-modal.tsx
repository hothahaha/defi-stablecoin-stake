import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { UserAsset } from "@/types";
import { parseUnits, formatUnits } from "ethers";
import { getLendingPoolContract, getSigner } from "@/lib/contract-utils";
import { useAccount } from "wagmi";

export function WithdrawModal({
    isOpen,
    onClose,
    asset,
    onSuccess,
}: {
    isOpen: boolean;
    onClose: () => void;
    asset: UserAsset;
    onSuccess: () => void;
}) {
    const [amount, setAmount] = useState("");
    const [isWaitingTx, setIsWaitingTx] = useState(false);
    const [maxWithdraw, setMaxWithdraw] = useState("0");
    const { address } = useAccount();

    const parsedAmount = amount ? parseUnits(amount, asset.decimals) : 0n;

    useEffect(() => {
        async function fetchMaxWithdraw() {
            if (!address) return;
            const signer = await getSigner();
            if (!signer) return;

            const contract = getLendingPoolContract(signer);
            if (!contract) return;

            try {
                const max = await contract.getMaxWithdrawAmount(address, asset.token);
                setMaxWithdraw(formatUnits(max, asset.decimals));
            } catch (error) {
                console.error("Failed to fetch max withdraw:", error);
            }
        }

        if (isOpen) {
            fetchMaxWithdraw();
        }
    }, [address, asset.token, asset.decimals, isOpen]);

    useEffect(() => {
        if (!isOpen) {
            setAmount("");
            setIsWaitingTx(false);
        }
    }, [isOpen]);

    const handleWithdraw = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!amount) return;

        try {
            setIsWaitingTx(true);
            const signer = await getSigner();
            if (!signer) throw new Error("No signer");

            const contract = getLendingPoolContract(signer);
            if (!contract) throw new Error("No contract");

            const tx = await contract.withdraw(asset.token, parsedAmount);

            await tx.wait();
            onSuccess?.();
            onClose();
        } catch (error) {
            console.error("Withdraw failed:", error);
            alert(error.message || "Withdraw failed");
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
                    <DialogTitle>Withdraw {asset.symbol}</DialogTitle>
                </DialogHeader>

                <form
                    className="space-y-4"
                    onSubmit={handleWithdraw}
                >
                    <div>
                        <Label>Withdraw Amount</Label>
                        <div className="flex items-center gap-2">
                            <Input
                                type="number"
                                value={amount}
                                onChange={(e) => setAmount(e.target.value)}
                                placeholder="Enter withdraw amount"
                            />
                            <Button
                                type="button"
                                variant="outline"
                                onClick={() => setAmount(maxWithdraw)}
                            >
                                Max
                            </Button>
                        </div>
                        <p className="text-sm text-muted-foreground mt-1">
                            Max Withdraw: {maxWithdraw} {asset.symbol}
                        </p>
                    </div>

                    <Button
                        type="submit"
                        className="w-full"
                        disabled={isWaitingTx}
                    >
                        {isWaitingTx ? "Processing..." : "Confirm Withdraw"}
                    </Button>
                </form>
            </DialogContent>
        </Dialog>
    );
}
