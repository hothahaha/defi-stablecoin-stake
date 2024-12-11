export function ErrorMessage({ message }: { message: string }) {
    return (
        <div className="rounded-lg bg-destructive/10 p-4 text-destructive">
            <p>{message}</p>
        </div>
    );
}
