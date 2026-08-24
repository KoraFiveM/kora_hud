import { Fuel, Gauge, Power, PowerOff, ShieldAlert, ShieldCheck } from "lucide-react"

import { useHudState } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

// Only rendered while `vehicle` (from the separate "qbhud:vehicle" message,
// sent faster than "qbhud:update" -- see client/hud.lua's pushVehicleUpdate)
// is present -- client/hud.lua sends null on foot -- and the vehicle element
// is enabled.
export function VehicleInfo() {
    const { config, vehicle } = useHudState()
    if (!config.elements.vehicle || !vehicle) return null

    const { speed, fuel, engineOn, seatbelt } = vehicle

    return (
        <div className="flex items-center gap-3">
            {fuel !== null && <RadialGauge icon={Fuel} value={fuel} label="Fuel" color={statColor(fuel)} size={36} stroke={3} />}
            <div className="hud-panel flex items-center gap-4 rounded-2xl px-5 py-3 font-mono overlay-text">
                <div className="flex items-baseline gap-1.5 text-foreground">
                    <Gauge className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
                    <span className="text-2xl font-bold leading-none tabular-nums">{Math.round(speed)}</span>
                    <span className="text-[10px] uppercase tracking-wide text-muted-foreground">km/h</span>
                </div>
                <div className="h-8 w-px bg-border" />
                <div className="flex items-center gap-2.5">
                    {engineOn ? (
                        <Power className="h-4 w-4 shrink-0 text-success" aria-label="Engine on" />
                    ) : (
                        <PowerOff className="h-4 w-4 shrink-0 text-muted-foreground" aria-label="Engine off" />
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
