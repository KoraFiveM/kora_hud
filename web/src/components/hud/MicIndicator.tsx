import { Mic, MicOff } from "lucide-react"

import { cn } from "@/lib/cn"
import { useHudConfig, useHudVitals } from "@/lib/hudState"

export function MicIndicator() {
    const config = useHudConfig()
    const vitals = useHudVitals()
    if (!config.elements.mic) return null

    const mode = vitals.voiceMode
    const activeStep = Math.max(1, Math.min(3, Math.round(mode?.index ?? 1)))
    const range = mode ? `${Number.isInteger(mode.range) ? mode.range : mode.range.toFixed(1)}m` : null

    return (
        <div
            className={cn(
                "hud-panel flex h-9 items-center rounded-full transition-all duration-fast",
                mode ? "px-2.5" : "w-9 justify-center",
                vitals.talking && "hud-panel-accent-success",
            )}
            aria-label={mode ? `Voice range: ${mode.label}, ${range}` : "Voice range unavailable"}
        >
            <div className="flex h-6 w-6 shrink-0 items-center justify-center">
                {vitals.talking ? (
                    <Mic className="h-4 w-4 animate-pulse text-success" aria-label="Talking" />
                ) : (
                    <MicOff className="h-4 w-4 text-muted-foreground" aria-label="Not talking" />
                )}
            </div>

            {mode && (
                <>
                    <div className="mx-2 h-4 w-px bg-border/70" />
                    <div className="flex items-end gap-0.5" aria-hidden="true">
                        {[1, 2, 3].map((step) => (
                            <span
                                key={step}
                                className={cn(
                                    "w-1 rounded-full bg-muted-foreground/35 transition-colors duration-fast",
                                    step <= activeStep && (vitals.talking ? "bg-success" : "bg-foreground/80"),
                                )}
                                style={{ height: `${5 + step * 3}px` }}
                            />
                        ))}
                    </div>
                    <div className="ml-2 flex min-w-0 items-baseline gap-1.5 overlay-text">
                        <span className="text-[11px] font-semibold leading-none text-foreground">{mode.label}</span>
                        <span className="font-mono text-[9px] leading-none text-muted-foreground">{range}</span>
                    </div>
                </>
            )}
        </div>
    )
}
