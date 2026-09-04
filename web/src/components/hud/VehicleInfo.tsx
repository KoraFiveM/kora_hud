import { BatteryCharging, Fuel, Lightbulb, LightbulbOff, Power, PowerOff, ShieldAlert, ShieldCheck, Sun } from "lucide-react"

import { useHudConfig, useHudVehicle } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

// Only rendered while `vehicle` (from the separate "qbhud:vehicle" message,
// sent faster than "qbhud:update" -- see client/hud.lua's pushVehicleUpdate)
// is present -- client/hud.lua sends null on foot -- and the vehicle element
// is enabled.
export function VehicleInfo() {
    const config = useHudConfig()
    const vehicle = useHudVehicle()
    if (!config.elements.vehicle || !vehicle) return null

    const { speed, fuel, fuelKind, engineOn, headlights, seatbelt } = vehicle
    const electric = fuelKind === "charge"

    return (
        <div className="flex items-center gap-3">
            {fuel !== null && (
                <RadialGauge icon={electric ? BatteryCharging : Fuel} value={fuel} defaultValue={100} label={electric ? "Charge" : "Fuel"} color={statColor(fuel)} size={36} stroke={3} />
            )}
            <div className="hud-panel flex items-center gap-4 rounded-2xl px-5 py-3 font-mono overlay-text">
                {/* No speedometer icon. "km/h" beside a large number already
                    says what this is, and a gauge glyph next to it was the one
                    decorative element in a row where every other icon reports
                    a live state (engine, lights, belt). */}
                <div className="flex items-baseline gap-1.5 text-foreground">
                    <span className="w-[4ch] text-right text-2xl font-bold leading-none tabular-nums">{Math.round(speed)}</span>
                    <span className="text-[10px] uppercase tracking-wide text-muted-foreground">km/h</span>
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
