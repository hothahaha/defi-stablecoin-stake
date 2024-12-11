import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { Navigation } from "@/components/layout/navigation";
import { Footer } from "@/components/layout/footer";
import { Providers } from "@/components/providers";
import { cn } from "@/lib/utils";
import "./globals.css";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
    title: "Mantle DeFi",
    description: "Mantle DeFi Lending Protocol",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
    return (
        <html
            lang="en"
            suppressHydrationWarning
        >
            <body
                className={cn(inter.className, "min-h-screen bg-background font-sans antialiased")}
            >
                <Providers>
                    <div className="relative flex min-h-screen flex-col">
                        <Navigation />
                        <main className="flex-1">{children}</main>
                        <Footer />
                    </div>
                </Providers>
            </body>
        </html>
    );
}
