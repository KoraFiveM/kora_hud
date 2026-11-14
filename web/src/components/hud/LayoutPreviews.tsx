import { useLocale } from "@/lib/hudState"

import { BatteryCharging, Brain, Droplets, Heart, Lightbulb, Power, Shield, ShieldCheck, Utensils, Zap, AlertTriangle } from "lucide-react"

import { RadialGauge } from "./RadialGauge"
import { useHudConfig, useHudLayout } from "@/lib/hudState"

// These are shown only while /hudlayout is open. They deliberately use the
// real HUD building blocks and representative values, so an element that is
// normally hidden (full gauges, on-foot vehicle data, no active effects) still
// has a truthful, useful footprint while the player positions its section.
export function GaugesPreview() {
    const t = useLocale()
    return (
        <div className="flex items-center gap-2">
            <RadialGauge icon={Heart} value={68} defaultValue={100} label={t("UI.health")} color="hsl(var(--success))" />
            <RadialGauge icon={Shield} value={42} defaultValue={0} label={t("UI.armour")} color="hsl(var(--armour))" />
            <RadialGauge icon={Zap} value={55} defaultValue={100} label={t("UI.stamina")} color="hsl(var(--warning))" />
            <RadialGauge icon={Utensils} value={64} defaultValue={100} label={t("UI.hunger")} color="hsl(var(--success))" />
            <RadialGauge icon={Droplets} value={48} defaultValue={100} label={t("UI.thirst")} color="hsl(var(--warning))" />
            <RadialGauge icon={Brain} value={35} defaultValue={0} label={t("UI.stress")} color="hsl(var(--warning))" />
        </div>
    )
}

export function VehiclePreview() {
    const t = useLocale()
    const config = useHudConfig()
    const mph = config.speedUnit === "mph"

    return (
        <div className="flex items-center gap-3">
            <RadialGauge icon={BatteryCharging} value={62} defaultValue={100} label={t("UI.fuel")} color="hsl(var(--warning))" size={36} stroke={3} />
            <div className="hud-panel flex items-center gap-4 rounded-2xl px-5 py-3 font-mono overlay-text">
                <div className="flex items-baseline gap-1.5 text-foreground">
                    <span className="w-[4ch] text-right text-2xl font-bold leading-none tabular-nums">{mph ? 53 : 86}</span>
                    <span className="text-[10px] uppercase tracking-wide text-muted-foreground">{mph ? "mph" : "km/h"}</span>
                </div>
                <div className="h-8 w-px bg-border" />
                <div className="flex items-center gap-2.5">
                    <Power className="h-4 w-4 shrink-0 text-success" aria-label={t("UI.engineOn")} />
                    <Lightbulb className="h-4 w-4 shrink-0 text-warning" aria-label={t("UI.headlightsOn")} />
                    <ShieldCheck className="h-4 w-4 shrink-0 text-success" aria-label={t("UI.seatbeltOn")} />
                </div>
            </div>
        </div>
    )
}

export function StatusPreview() {
    const t = useLocale()
    const layout = useHudLayout()
    const alignment = layout.justifications.status ?? "right"
    return (
        <div className={`flex flex-col gap-1.5 ${alignment === "left" ? "items-start" : alignment === "center" ? "items-center" : "items-end"}`}>
            <div className="hud-panel flex items-center gap-2 rounded-full py-1.5 pl-2 pr-3.5 overlay-text">
                <span className="icon-badge icon-badge-destructive">
                    <AlertTriangle className="h-3.5 w-3.5" aria-hidden />
                </span>
                <span className="text-xs font-medium">{t("UI.bleeding")} · 2</span>
            </div>
            <div className="hud-panel flex items-center gap-2 rounded-full py-1.5 pl-2 pr-3.5 overlay-text">
                <span className="icon-badge icon-badge-destructive">
                    <AlertTriangle className="h-3.5 w-3.5" aria-hidden />
                </span>
                <span className="text-xs font-medium">{t("UI.limping")}</span>
            </div>
        </div>
    )
}
