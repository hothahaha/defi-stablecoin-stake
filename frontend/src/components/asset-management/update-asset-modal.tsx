import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { getAssetManagerContract, getSigner } from "@/lib/contract-utils";
import { Asset } from "@/types";
import { parseUnits, formatUnits } from "ethers";
import { useAssets } from "@/hooks/use-assets";

interface UpdateAssetModalProps {
    isOpen: boolean;
    onClose: () => void;
    asset: Asset;
    onSuccess?: () => void;
}

export function UpdateAssetModal({ isOpen, onClose, asset, onSuccess }: UpdateAssetModalProps) {
    const [isWaitingTx, setIsWaitingTx] = useState(false);
    const { refetch } = useAssets();
    const [formData, setFormData] = useState({
        collateralFactor: "0",
        borrowFactor: "0",
    });

    // Set default values when opening
    useEffect(() => {
        if (isOpen && asset) {
            setFormData({
                collateralFactor: Number(formatUnits(asset.config.collateralFactor, 16)).toFixed(0),
                borrowFactor: Number(formatUnits(asset.config.borrowFactor, 16)).toFixed(0),
            });
            setIsWaitingTx(false);
        }
    }, [isOpen, asset]);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();

        try {
            setIsWaitingTx(true);
            const signer = await getSigner();
            if (!signer) throw new Error("No signer");

            const contract = getAssetManagerContract(signer);
            if (!contract) throw new Error("No contract");

            // Merge existing config with new changes
            const updatedConfig = {
                isSupported: true,
                collateralFactor: parseUnits(
                    (Number(formData.collateralFactor) / 100).toString(),
                    18
                ),
                borrowFactor: parseUnits(
                    (Number(formData.borrowFactor) / 100).toString(),
                    18
                ),
                symbol: asset.config.symbol,
                name: asset.config.name,
                decimals: asset.config.decimals,
                icon: asset.config.icon,
            };

            console.log("Updating asset with config:", {
                token: asset.token,
                config: updatedConfig,
            });

            const tx = await contract.updateAsset(asset.token, updatedConfig);

            console.log("Transaction sent:", tx.hash);
            await tx.wait();
            console.log("Transaction confirmed");

            await refetch();
            onSuccess?.();
            onClose();
        } catch (error) {
            console.error("Update asset failed:", error);
            // 添加更详细的错误信息
            if (error.data) {
                console.error("Error data:", error.data);
            }
            if (error.transaction) {
                console.error("Transaction:", error.transaction);
            }
            alert(error.message || "Failed to update asset");
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
                    <DialogTitle>Update Asset - {asset.config.symbol}</DialogTitle>
                </DialogHeader>

                <form
                    onSubmit={handleSubmit}
                    className="space-y-4"
                >
                    <div>
                        <Label>Collateral Factor (0-100)</Label>
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
                            min="0"
                            max="100"
                            step="1"
                            disabled={isWaitingTx}
                        />
                    </div>

                    <div>
                        <Label>Borrow Factor (0-100)</Label>
                        <Input
                            type="number"
                            value={formData.borrowFactor}
                            onChange={(e) =>
                                setFormData((prev) => ({ ...prev, borrowFactor: e.target.value }))
                            }
                            placeholder="e.g., 90"
                            min="0"
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
