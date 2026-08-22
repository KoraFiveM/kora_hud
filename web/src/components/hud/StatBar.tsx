import type { LucideIcon } from "lucide-react"

import { cn } from "@/lib/cn"

interface StatBarProps {
    icon: LucideIcon
    value: number
    colorClassName?: string
    label: string
}

/**
 * Shared glanceable meter every stat element (health/armour/stamina/hunger/
 * thirst/stress) renders through, so they look and behave identically.
 * `value` is clamped to 0-100 -- callers convert whatever native range their
 * stat uses (e.g. health's 100-200) before passing it in.
 */
export function StatBar({ icon: Icon, value, colorClassName = "bg-primary", label }: StatBarProps) {
    const clamped = Math.max(0, Math.min(100, value))

    return (
        <div className="flex items-center gap-2">
            <Icon className="h-4 w-4 shrink-0 text-foreground overlay-text" aria-hidden />
            <div
                className="h-1.5 w-20 overflow-hidden rounded-full bg-muted"
                role="meter"
                aria-label={label}
                aria-valuemin={0}
                aria-valuemax={100}
                aria-valuenow={Math.round(clamped)}
            >
                <div className={cn("h-full rounded-full transition-[width] duration-fast", colorClassName)} style={{ width: `${clamped}%` }} />
            </div>
        </div>
    )
}
