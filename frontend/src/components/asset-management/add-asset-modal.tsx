import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { getLendingPoolContract, getSigner } from "@/lib/contract-utils";
import { parseUnits } from "ethers";

interface AddAssetModalProps {
    isOpen: boolean;
    onClose: () => void;
    onSuccess?: () => void;
}

export function AddAssetModal({ isOpen, onClose, onSuccess }: AddAssetModalProps) {
    const [isWaitingTx, setIsWaitingTx] = useState(false);
    const [formData, setFormData] = useState({
        token: "",
        priceFeed: "",
        name: "",
        symbol: "",
        decimals: "18",
        icon: "",
        collateralFactor: "80",
        borrowFactor: "90",
    });

    // 关闭时重置表单
    useEffect(() => {
        if (!isOpen) {
            setFormData({
                token: "",
                priceFeed: "",
                name: "",
                symbol: "",
                decimals: "18",
                icon: "",
                collateralFactor: "80",
                borrowFactor: "90",
            });
            setIsWaitingTx(false);
        }
    }, [isOpen]);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!formData.token || !formData.priceFeed) return;

        try {
            setIsWaitingTx(true);
            const signer = await getSigner();
            if (!signer) throw new Error("No signer");

            const contract = getLendingPoolContract(signer);
            if (!contract) throw new Error("No contract");

            const tx = await contract.addAsset(
                formData.token,
                formData.priceFeed,
                {
                    isSupported: true,
                    name: formData.name,
                    symbol: formData.symbol,
                    decimals: parseInt(formData.decimals),
                    icon: formData.icon,
                    collateralFactor: parseUnits(
                        (Number(formData.collateralFactor) / 100).toString(),
                        18
                    ),
                    borrowFactor: parseUnits((Number(formData.borrowFactor) / 100).toString(), 18),
                },
                { gasLimit: 500000n }
            );

            await tx.wait();
            onSuccess?.();
            onClose();
        } catch (error) {
            console.error("Add asset failed:", error);
            alert(error.message || "Failed to add asset");
        } finally {
            setIsWaitingTx(false);
        }
    };

    return (
        <Dialog open={isOpen} onOpenChange={onClose}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Add New Asset</DialogTitle>
                </DialogHeader>

                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <Label>Token Address</Label>
                        <Input
                            value={formData.token}
                            onChange={(e) =>
                                setFormData((prev) => ({ ...prev, token: e.target.value }))
                            }
                            placeholder="Enter token contract address"
                            disabled={isWaitingTx}
                        />
                    </div>

                    <div>
                        <Label>Price Feed Address</Label>
                        <Input
                            value={formData.priceFeed}
                            onChange={(e) =>
                                setFormData((prev) => ({ ...prev, priceFeed: e.target.value }))
                            }
                            placeholder="Enter price feed address"
                            disabled={isWaitingTx}
                        />
                    </div>

                    <div>
                        <Label>Token Name</Label>
                        <Input
                            value={formData.name}
                            onChange={(e) =>
                                setFormData((prev) => ({ ...prev, name: e.target.value }))
                            }
                            placeholder="e.g., Ethereum"
                            disabled={isWaitingTx}
                        />
                    </div>

                    <div>
                        <Label>Token Symbol</Label>
                        <Input
                            value={formData.symbol}
                            onChange={(e) =>
                                setFormData((prev) => ({ ...prev, symbol: e.target.value }))
                            }
                            placeholder="e.g., ETH"
                            disabled={isWaitingTx}
                        />
                    </div>

                    <div>
                        <Label>Decimals</Label>
                        <Input
                            type="number"
                            value={formData.decimals}
                            onChange={(e) =>
                                setFormData((prev) => ({ ...prev, decimals: e.target.value }))
                            }
                            placeholder="e.g., 18"
                            disabled={isWaitingTx}
                        />
                    </div>

                    <div>
                        <Label>Icon URL</Label>
                        <Input
                            value={formData.icon}
                            onChange={(e) =>
                                setFormData((prev) => ({ ...prev, icon: e.target.value }))
                            }
                            placeholder="Enter icon URL"
                            disabled={isWaitingTx}
                        />
                    </div>

                    <div>
                        <Label>Collateral Factor (1-100)</Label>
                        <Input
                            type="number"
                            value={formData.collateralFactor}
                            onChange={(e) =>
                                setFormData((prev) => ({
                                    ...prev,
                                    collateralFactor: e.target.value,
                                }))
                            }
                            placeholder="e.g., 80"
                            min="1"
                            max="100"
                            step="1"
                            disabled={isWaitingTx}
                        />
                    </div>

                    <div>
                        <Label>Borrow Factor (1-100)</Label>
                        <Input
                            type="number"
                            value={formData.borrowFactor}
                            onChange={(e) =>
                                setFormData((prev) => ({ ...prev, borrowFactor: e.target.value }))
                            }
                            placeholder="e.g., 90"
                            min="1"
                            max="100"
                            step="1"
                            disabled={isWaitingTx}
                        />
                    </div>

                    <Button
                        type="submit"
                        className="w-full"
                        disabled={isWaitingTx}
                    >
                        {isWaitingTx ? "Processing..." : "Confirm"}
                    </Button>
                </form>
            </DialogContent>
        </Dialog>
    );
}
