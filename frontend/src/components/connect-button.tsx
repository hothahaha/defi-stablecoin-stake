import { Button } from "@/components/ui/button";
import { useAccount, useConnect, useDisconnect } from "wagmi";

export function ConnectButton() {
  const { address } = useAccount();
  const { connect } = useConnect();
  const { disconnect } = useDisconnect();

  return (
    <Button onClick={() => address ? disconnect() : connect()}>
      {address ? '断开连接' : '连接钱包'}
    </Button>
  );
} 