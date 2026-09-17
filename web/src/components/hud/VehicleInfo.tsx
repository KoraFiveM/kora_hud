import { BatteryCharging, Fuel, Lightbulb, LightbulbOff, Power, PowerOff, ShieldAlert, ShieldCheck, Sun } from "lucide-react"

import { useHudConfig, useHudVehicle } from "@/lib/hudState"
import { cn } from "@/lib/cn"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

// The panel retains its geometry while hidden so it can translate in from the
// bottom instead of popping into existence when client/hud.lua sends a vehicle
// snapshot. It remains visually and accessibly absent while on foot.
export function VehicleInfo() {
    const config = useHudConfig()
    const vehicle = useHudVehicle()
    if (!config.elements.vehicle) return null

    const active = vehicle !== null
    const { speed = 0, speedUnit = config.speedUnit, fuel = null, fuelKind = "fuel", engineOn = false, headlights = "off", seatbelt = false } = vehicle ?? {}
    const electric = fuelKind === "charge"
    const speedLabel = speedUnit === "mph" ? "mph" : "km/h"

    return (
        <div className={cn("flex items-center gap-3 transition-[opacity,transform] duration-200 ease-out", active ? "translate-y-0 opacity-100" : "translate-y-[calc(100%+1rem)] opacity-0")} aria-hidden={!active}>
            {fuel !== null && (
                <RadialGauge icon={electric ? BatteryCharging : Fuel} value={fuel} defaultValue={100} label={electric ? "Charge" : "Fuel"} color={statColor(fuel)} size={36} stroke={3} />
            )}
            <div className="hud-panel flex items-center gap-4 rounded-2xl px-5 py-3 font-mono overlay-text">
                {/* No speedometer icon. The unit beside a large number already
                    says what this is, and a gauge glyph next to it was the one
                    decorative element in a row where every other icon reports
                    a live state (engine, lights, belt). */}
                <div className="flex items-baseline gap-1.5 text-foreground">
                    <span className="w-[4ch] text-right text-2xl font-bold leading-none tabular-nums">{Math.round(speed)}</span>
                    <span className="text-[10px] uppercase tracking-wide text-muted-foreground">{speedLabel}</span>
                </div>
                <div className="h-8 w-px bg-border" />
                <div className="flex items-center gap-2.5">
                    {engineOn ? (
                        <Power className="h-4 w-4 shrink-0 text-success" aria-label="Engine on" />
                    ) : (
                        <PowerOff className="h-4 w-4 shrink-0 text-muted-foreground" aria-label="Engine off" />
                    )}
                    {headlights === "high" ? (
                        <Sun className="h-4 w-4 shrink-0 text-info" aria-label="High beams on" />
                    ) : headlights === "low" ? (
                        <Lightbulb className="h-4 w-4 shrink-0 text-warning" aria-label="Headlights on" />
                    ) : (
                        <LightbulbOff className="h-4 w-4 shrink-0 text-muted-foreground" aria-label="Headlights off" />
                    )}
                    {seatbelt ? (
                        <ShieldCheck className="h-4 w-4 shrink-0 text-success" aria-label="Seatbelt on" />
                    ) : (
                        <ShieldAlert className="h-4 w-4 shrink-0 animate-pulse text-warning" aria-label="Seatbelt off" />
                    )}
                </div>
            </div>
        </div>
    )
}
