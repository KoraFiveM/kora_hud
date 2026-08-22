import { Mic, MicOff } from "lucide-react"

import { cn } from "@/lib/cn"
import { useHudState } from "@/lib/hudState"

export function MicIndicator() {
    const { config, update } = useHudState()
    if (!config.elements.mic) return null

    return (
        <div className={cn("hud-chip flex items-center justify-center p-2 transition-colors duration-fast", update.talking && "hud-chip-accent")}>
            {update.talking ? (
                <Mic className="h-4 w-4 text-primary" aria-label="Talking" />
            ) : (
                <MicOff className="h-4 w-4 text-muted-foreground" aria-label="Not talking" />
            )}
        </div>
    )
}
