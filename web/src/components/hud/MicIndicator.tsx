import { Mic, MicOff } from "lucide-react"

import { cn } from "@/lib/cn"
import { useHudConfig, useHudVitals } from "@/lib/hudState"

export function MicIndicator() {
    const config = useHudConfig()
    const vitals = useHudVitals()
    if (!config.elements.mic) return null

    return (
        <div
            className={cn(
                "hud-panel flex h-9 w-9 items-center justify-center rounded-full transition-colors duration-fast",
                vitals.talking && "hud-panel-accent-success",
            )}
        >
            {vitals.talking ? (
                <Mic className="h-4 w-4 animate-pulse text-success" aria-label="Talking" />
            ) : (
                <MicOff className="h-4 w-4 text-muted-foreground" aria-label="Not talking" />
            )}
        </div>
    )
}
