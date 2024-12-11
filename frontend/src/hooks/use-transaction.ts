import { useState } from 'react';
import { useToast } from '@/components/ui/use-toast';

export function useTransaction() {
    const [isPending, setIsPending] = useState(false);
    const [error, setError] = useState<Error>();
    const { toast } = useToast();

    const handleTransaction = async (
        promise: Promise<any>,
        {
            onSuccess,
            onError,
        }: {
            onSuccess?: () => void;
            onError?: (error: Error) => void;
        } = {}
    ) => {
        try {
            setIsPending(true);
            setError(undefined);
            const result = await promise;

            toast({
                title: "交易成功",
                description: "您的交易已被确认"
            });

            onSuccess?.();
            return result;
        } catch (e) {
            const error = e as Error;
            setError(error);

            toast({
                title: "交易失败",
                description: error.message
            });

            onError?.(error);
            throw error;
        } finally {
            setIsPending(false);
        }
    };

    return {
        isPending,
        error,
        handleTransaction,
    };
}
