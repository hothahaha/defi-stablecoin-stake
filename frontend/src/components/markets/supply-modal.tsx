import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { useAccount } from "wagmi";
import { Asset } from "@/types";
import { parseUnits, formatUnits, MaxUint256 } from "ethers";
import { getLendingPoolContract, getERC20Contract, getSigner } from "@/lib/contract-utils";

const DEPOSIT_ERRORS = {
    "0xe450d38c": "LendingPool__InvalidAmount",
    "0xfb8f41b2": "LendingPool__InsufficientAllowance",
} as const;

export function SupplyModal({
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
    const [isApproving, setIsApproving] = useState(false);
    const [isWaitingTx, setIsWaitingTx] = useState(false);
    const [balance, setBalance] = useState("0");
    const [allowance, setAllowance] = useState("0");
    const { address } = useAccount();

    const parsedAmount = amount ? parseUnits(amount, 18) : 0n;

    useEffect(() => {
        async function fetchData() {
            if (!address) return;
            const signer = await getSigner();
            if (!signer) return;

            const tokenContract = getERC20Contract(asset.token, signer);
            if (!tokenContract) return;

            const [balanceResult, allowanceResult] = await Promise.all([
                tokenContract.balanceOf(address),
                tokenContract.allowance(address, getLendingPoolContract()?.target),
            ]);

            setBalance(formatUnits(balanceResult, asset.config.decimals));
            setAllowance(allowanceResult.toString());
        }

        fetchData();
    }, [address, asset.token, asset.config.decimals]);

    useEffect(() => {
        if (!isOpen) {
            setAmount("");
            setIsApproving(false);
            setIsWaitingTx(false);
        }
    }, [isOpen]);

    const handleApprove = async () => {
        try {
            setIsApproving(true);
            const signer = await getSigner();
            if (!signer) throw new Error("No signer");

            const tokenContract = getERC20Contract(asset.token, signer);
            if (!tokenContract) throw new Error("No contract");

            const tx = await tokenContract.approve(getLendingPoolContract()?.target, MaxUint256);
            setIsWaitingTx(true);
            await tx.wait();
            setAllowance(MaxUint256.toString());
        } catch (error) {
            console.error("Approve failed:", error);
        } finally {
            setIsWaitingTx(false);
            setIsApproving(false);
        }
    };

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!amount) return;

        try {
            setIsWaitingTx(true);
            const signer = await getSigner();
            if (!signer) throw new Error("No signer");

            const contract = getLendingPoolContract(signer);
            if (!contract) throw new Error("No lending pool contract");

            console.log("Deposit call:", {
                token: asset.token,
                amount: parsedAmount.toString(),
                contract: contract.target,
                encodedData: contract.interface.encodeFunctionData("deposit", [
                    asset.token,
                    parsedAmount,
                ]),
            });

            const tx = await contract.deposit(asset.token, parsedAmount, {
                value: 0n,
            });

            console.log("Transaction sent:", tx.hash);
            await tx.wait();
            onSuccess?.(); // 调用成功回调
            onClose();
            setAmount("");
        } catch (error: any) {
            console.error("Deposit failed:", {
                error,
                errorData: error?.data,
                errorMessage: error?.message,
                transaction: error?.transaction,
            });
            alert(error.message || "Deposit failed");
        } finally {
            setIsWaitingTx(false);
        }
    };

    const needsApproval = BigInt(allowance) < parsedAmount;
    const buttonDisabled = isApproving || isWaitingTx;
    const buttonHandler = needsApproval ? handleApprove : handleSubmit;

    const buttonContent = () => {
        if (isWaitingTx) return "Waiting for transaction confirmation...";
        if (isApproving) return "Authorizing...";
        if (needsApproval) return "Authorize Token";
        return "Confirm Deposit";
    };

    return (
        <Dialog
            open={isOpen}
            onOpenChange={onClose}
        >
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Deposit {asset.config.symbol}</DialogTitle>
                </DialogHeader>

                <form
                    onSubmit={(e) => {
                        e.preventDefault();
                        buttonHandler(e);
                    }}
                >
                    <div className="space-y-4">
                        <div>
                            <div className="flex items-center gap-2">
                                <Input
                                    type="number"
                                    value={amount}
                                    onChange={(e) => setAmount(e.target.value)}
                                    placeholder="Enter deposit amount"
                                />
                                <Button
                                    type="button"
                                    variant="outline"
                                    onClick={() => setAmount(balance ?? "0")}
                                >
                                    Max
                                </Button>
                            </div>
                            <div className="text-sm text-muted-foreground mt-1">
                                Max Deposit: {balance} {asset.config.symbol}
                            </div>
                        </div>

                        <Button
                            type="submit"
                            className="w-full"
                            disabled={buttonDisabled}
                        >
                            {buttonContent()}
                        </Button>
                    </div>
                </form>
            </DialogContent>
        </Dialog>
    );
}
