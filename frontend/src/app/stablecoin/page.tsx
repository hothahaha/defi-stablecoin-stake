import { StablecoinMint } from "@/components/stablecoin/stablecoin-mint";
import { StablecoinBurn } from "@/components/stablecoin/stablecoin-burn";

export default function StableCoinPage() {
    return (
        <div className="container py-6">
            <h1 className="text-2xl font-bold mb-6">稳定币操作</h1>

            <div className="grid md:grid-cols-2 gap-6">
                <StablecoinMint />
                <StablecoinBurn />
            </div>
        </div>
    );
}
