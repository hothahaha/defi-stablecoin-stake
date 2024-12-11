"use client";

import { Toast } from "./toast";
import { useToast } from "./use-toast";

export function Toaster() {
    const { toasts } = useToast();

    return (
        <div className="fixed top-0 z-[100] flex max-h-screen w-full flex-col-reverse p-4 sm:bottom-0 sm:right-0 sm:top-auto sm:flex-col md:max-w-[420px]">
            {toasts.map(function ({ id, title, description, action, ...props }) {
                return (
                    <Toast
                        key={id}
                        {...props}
                    >
                        {title}
                    </Toast>
                );
            })}
        </div>
    );
}
