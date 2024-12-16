"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount } from "wagmi";
import { useEffect } from "react";
import { useRouter } from "next/navigation";

const navigation = [
    { name: "Market", href: "/markets" },
    { name: "My Assets", href: "/admin" },
    { name: "Asset Management", href: "/asset-management" },
] as const;

export function Navigation() {
    const pathname = usePathname();
    const { address } = useAccount();
    const router = useRouter();

    useEffect(() => {
        if (address) {
            // 当钱包连接时，强制刷新当前页面
            if (pathname === "/") {
                router.push("/markets");
            } else {
                // 重新导航到当前页面来触发刷新
                router.refresh();
                router.push(pathname);
            }
        }
    }, [address, pathname, router]);

    return (
        <header className="sticky top-0 z-40 w-full border-b bg-background">
            <div className="container flex h-16 items-center justify-between">
                <div className="flex items-center gap-6">
                    <div className="font-bold text-primary">Pure DeFi</div>

                    <nav className="flex items-center gap-4">
                        {navigation.map((item) => (
                            <Link
                                key={item.href}
                                href={item.href}
                                className={cn(
                                    "text-sm font-medium transition-colors",
                                    pathname === item.href
                                        ? "text-primary"
                                        : "text-muted-foreground hover:text-primary"
                                )}
                            >
                                {item.name}
                            </Link>
                        ))}
                    </nav>
                </div>

                <div className="flex items-center gap-4">
                    <ConnectButton />
                </div>
            </div>
        </header>
    );
}
