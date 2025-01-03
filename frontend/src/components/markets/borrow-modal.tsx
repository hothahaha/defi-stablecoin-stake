import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { useAccount } from "wagmi";
import { Asset } from "@/types";
import { parseUnits, formatUnits } from "ethers";
import { getLendingPoolContract, getSigner } from "@/lib/contract-utils";

export function BorrowModal({
    isOpen,
    onClose,
    asset,
    onSuccess,
}: {
    isOpen: boolean;
    onClose: () => void;
    asset: Asset;
    onSuccess?: () => void;
}) {
    const [amount, setAmount] = useState("");
    const [isWaitingTx, setIsWaitingTx] = useState(false);
    const [borrowLimit, setBorrowLimit] = useState("0");
    const { address } = useAccount();

    const parsedAmount = amount ? parseUnits(amount, 18) : 0n;

    useEffect(() => {
        async function fetchBorrowLimit() {
            if (!address) return;
            const signer = await getSigner();
            if (!signer) return;

            const contract = getLendingPoolContract(signer);
            if (!contract) return;

            try {
                const limit = await contract.getUserBorrowLimit(address, asset.token);
                setBorrowLimit(formatUnits(limit, asset.config.decimals));
            } catch (error) {
                console.error("Failed to fetch borrow limit:", error);
            }
        }

        if (isOpen) {
            fetchBorrowLimit();
        }
    }, [address, asset.token, asset.config.decimals, isOpen]);

    useEffect(() => {
        if (!isOpen) {
            setAmount("");
            setIsWaitingTx(false);
        }
    }, [isOpen]);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!amount) return;

        try {
            setIsWaitingTx(true);
            const signer = await getSigner();
            if (!signer) throw new Error("No signer");

            const contract = getLendingPoolContract(signer);
            if (!contract) throw new Error("No lending pool contract");

            const tx = await contract.borrow(asset.token, parsedAmount);

            await tx.wait();
            onSuccess?.();
            onClose();
            setAmount("");
        } catch (error: any) {
            console.error("Borrow failed:", error);
            alert(error.message || "Borrow failed");
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
                    <DialogTitle>Borrow {asset.config.symbol}</DialogTitle>
                </DialogHeader>

                <form onSubmit={handleSubmit}>
                    <div className="space-y-4">
                        <div>
                            <div className="flex items-center gap-2">
                                <Input
                                    type="number"
                                    value={amount}
                                    onChange={(e) => setAmount(e.target.value)}
                                    placeholder="Enter borrow amount"
                                />
                                <Button
                                    type="button"
                                    variant="outline"
                                    onClick={() => setAmount(borrowLimit)}
                                >
                                    Max
                                </Button>
                            </div>
                            <div className="text-sm text-muted-foreground mt-1">
                                Max Borrow: {borrowLimit} {asset.config.symbol}
                            </div>
                        </div>

                        <Button
                            type="submit"
                            className="w-full"
                            disabled={isWaitingTx}
                        >
                            {isWaitingTx ? "Processing..." : "Confirm Borrow"}
                        </Button>
                    </div>
                </form>
            </DialogContent>
        </Dialog>
    );
}
