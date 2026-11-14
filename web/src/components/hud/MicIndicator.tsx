import { Volume, Volume1, Volume2 } from "lucide-react"

import { cn } from "@/lib/cn"
import { useHudConfig, useHudVitals, useLocale } from "@/lib/hudState"

export function MicIndicator() {
    const t = useLocale()
    const config = useHudConfig()
    const vitals = useHudVitals()
    if (!config.elements.mic) return null

    const mode = vitals.voiceMode
    const voiceMode = Math.max(1, Math.min(3, Math.round(mode?.index ?? 2)))
    const VoiceIcon = voiceMode === 1 ? Volume : voiceMode === 3 ? Volume2 : Volume1
    const voiceLabel = voiceMode === 1 ? t("UI.whisper") : voiceMode === 3 ? t("UI.shout") : t("UI.normalTalk")

    return (
        <div
            className={cn(
                "hud-panel flex h-9 w-9 items-center justify-center rounded-full transition-all duration-fast",
                vitals.talking && "hud-panel-accent-success",
            )}
            aria-label={t("UI.voiceRange", voiceLabel)}
            title={t("UI.voiceRange", voiceLabel)}
        >
            <VoiceIcon
                className={cn("h-4 w-4", vitals.talking ? "animate-pulse text-success" : "text-muted-foreground")}
                aria-hidden="true"
            />
        </div>
    )
}
