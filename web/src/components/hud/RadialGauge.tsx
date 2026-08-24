import type { LucideIcon } from "lucide-react"

import { cn } from "@/lib/cn"

interface RadialGaugeProps {
    icon: LucideIcon
    value: number
    label: string
    color: string
    size?: number
    stroke?: number
    /**
     * Pulses the ring once it's colored destructive. Keyed off `color`
     * rather than a raw value threshold since "critical" is direction-
     * dependent -- a low value for health, but a high one for stress (see
     * statColor's `invert`) -- and `color` already resolved that via
     * whatever banding the caller used.
     */
    pulse?: boolean
}

// Padding between the ring and its own circular glass panel -- same on
// every gauge regardless of `size` so a row of differently-sized gauges
// (e.g. the 44px vitals next to the 36px vehicle fuel gauge) still reads as
// one consistent badge shape rather than mismatched ring-to-panel ratios.
const PANEL_PADDING = 8

/**
 * Shared glanceable meter every vital (health/armour/stamina/hunger/thirst/
 * stress/fuel) renders through, so they look and behave identically. `value`
 * is clamped to 0-100 -- callers convert whatever native range their stat
 * uses (e.g. health's 100-200) before passing it in. Each gauge is its own
 * circular hud-panel badge -- not grouped inside a shared rectangle -- so a
 * row of them reads as separate glanceable dials, same idea as the mic
 * indicator's own circular badge.
 */
export function RadialGauge({ icon: Icon, value, label, color, size = 44, stroke = 3.5, pulse = false }: RadialGaugeProps) {
    const clamped = Math.max(0, Math.min(100, value))
    const radius = size / 2 - stroke
    const circumference = radius * 2 * Math.PI
    const offset = circumference * (1 - clamped / 100)
    const panelSize = size + PANEL_PADDING * 2

    return (
        <div
            className={cn(
                "hud-panel relative flex shrink-0 items-center justify-center rounded-full",
                pulse && color === "hsl(var(--destructive))" && "animate-pulse",
            )}
            style={{ width: panelSize, height: panelSize }}
            role="meter"
            aria-label={label}
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={Math.round(clamped)}
            title={`${label}: ${Math.round(clamped)}%`}
        >
            <svg width={size} height={size} className="-rotate-90">
                <circle cx={size / 2} cy={size / 2} r={radius} fill="none" stroke="hsl(var(--muted))" strokeWidth={stroke} />
                <circle
                    cx={size / 2}
                    cy={size / 2}
                    r={radius}
                    fill="none"
                    stroke={color}
                    strokeWidth={stroke}
                    strokeLinecap="round"
                    strokeDasharray={circumference}
                    strokeDashoffset={offset}
                    className="transition-[stroke-dashoffset,stroke] duration-fast"
                />
            </svg>
            <Icon className="absolute h-4 w-4 text-foreground overlay-text" aria-hidden />
        </div>
    )
}
