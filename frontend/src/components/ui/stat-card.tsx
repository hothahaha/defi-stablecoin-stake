import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

interface StatCardProps {
  title: string;
  value: string;
  change?: string;
  valuePrefix?: string;
  type?: 'default' | 'warning';
}

export function StatCard({ title, value, change, valuePrefix = '', type = 'default' }: StatCardProps) {
  return (
    <Card className="p-6">
      <p className="text-sm text-muted-foreground">{title}</p>
      <p className={cn(
        "text-2xl font-bold mt-2",
        type === 'warning' && "text-yellow-500"
      )}>
        {valuePrefix}{value}
      </p>
      {change && (
        <p className="text-sm text-green-500 mt-1">{change}</p>
      )}
    </Card>
  );
} 