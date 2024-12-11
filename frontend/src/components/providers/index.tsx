"use client";

import { WagmiConfig } from "wagmi";
import {
    RainbowKitProvider,
    connectorsForWallets,
    getDefaultConfig,
    darkTheme,
} from "@rainbow-me/rainbowkit";
import { rainbowWallet, walletConnectWallet } from "@rainbow-me/rainbowkit/wallets";
import { mantleSepolia, local } from "../../lib/contract-config";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import "@rainbow-me/rainbowkit/styles.css";

const projectId = "YOUR_PROJECT_ID";
const appName = "DeFi 借贷平台";
const queryClient = new QueryClient();

const connectors = connectorsForWallets(
    [
        {
            groupName: "推荐",
            wallets: [rainbowWallet, walletConnectWallet],
        },
    ],
    {
        appName,
        projectId,
    }
);

const config = getDefaultConfig({
    appName: appName,
    projectId: projectId,
    chains: [mantleSepolia, local],
});

export function Providers({ children }: { children: React.ReactNode }) {
    return (
        <QueryClientProvider client={queryClient}>
            <WagmiConfig config={config}>
                <RainbowKitProvider
                    theme={darkTheme({
                        accentColor: "#000000",
                        accentColorForeground: "#ffffff",
                        borderRadius: "small",
                        fontStack: "system",
                    })}
                    modalSize="compact"
                    coolMode
                    showRecentTransactions
                    appInfo={{
                        appName,
                    }}
                >
                    {children}
                </RainbowKitProvider>
            </WagmiConfig>
        </QueryClientProvider>
    );
}
