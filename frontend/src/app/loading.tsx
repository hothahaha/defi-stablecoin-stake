import { LoadingSpinner } from "@/components/ui/loading-spinner";

export default function Loading() {
    return (
        <div className="container py-12">
            <div className="flex justify-center">
                <LoadingSpinner />
            </div>
        </div>
    );
}
