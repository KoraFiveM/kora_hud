import { Hash } from "lucide-react"

import { useHudPlayerId, useLocale } from "@/lib/hudState"

/** A deliberately opt-in local server-ID badge, toggled by `/id`. */
export function PlayerId() {
    const t = useLocale()
    const playerId = useHudPlayerId()
    if (playerId === null) return null

    return (
        <div className="hud-panel flex items-center gap-2 rounded-full px-3 py-1.5 text-xs font-mono text-foreground overlay-text" aria-label={t("UI.playerId", playerId)}>
            <Hash className="h-3.5 w-3.5 text-primary" aria-hidden />
            <span>{t("UI.id", playerId)}</span>
        </div>
    )
}
