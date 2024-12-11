"use client";

import { Button } from "@/components/ui/button";

export default function Error({ error, reset }: { error: Error; reset: () => void }) {
    return (
        <div className="container py-12">
            <div className="flex flex-col items-center gap-4">
                <h1 className="text-2xl font-bold">出错了</h1>
                <p className="text-muted-foreground">{error.message}</p>
                <Button onClick={reset}>重试</Button>
            </div>
        </div>
    );
}
