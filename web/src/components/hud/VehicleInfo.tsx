import { Fuel, Gauge, Power, PowerOff, ShieldAlert, ShieldCheck } from "lucide-react"

import { useHudState } from "@/lib/hudState"

// Only rendered while update.vehicle is present (client/hud.lua sends null
// on foot) and the vehicle element is enabled.
export function VehicleInfo() {
    const { config, update } = useHudState()
    if (!config.elements.vehicle || !update.vehicle) return null

    const { speed, fuel, engineOn, seatbelt } = update.vehicle

    return (
        <div className="hud-chip flex items-center gap-4 px-4 py-2 text-sm font-mono overlay-text">
            <div className="flex items-center gap-2 text-foreground">
                <Gauge className="h-4 w-4 shrink-0" aria-hidden />
                <span>{Math.round(speed)} km/h</span>
            </div>
            {fuel !== null && (
                <div className="flex items-center gap-2 text-foreground">
                    <Fuel className="h-4 w-4 shrink-0" aria-hidden />
                    <span>{Math.round(fuel)}%</span>
                </div>
            )}
            <div title={engineOn ? "Engine on" : "Engine off"}>
                {engineOn ? (
                    <Power className="h-4 w-4 shrink-0 text-success" aria-label="Engine on" />
                ) : (
                    <PowerOff className="h-4 w-4 shrink-0 text-muted-foreground" aria-label="Engine off" />
                )}
            </div>
            <div title={seatbelt ? "Seatbelt on" : "Seatbelt off"}>
                {seatbelt ? (
                    <ShieldCheck className="h-4 w-4 shrink-0 text-success" aria-label="Seatbelt on" />
                ) : (
                    <ShieldAlert className="h-4 w-4 shrink-0 text-warning" aria-label="Seatbelt off" />
                )}
            </div>
        </div>
    )
}
