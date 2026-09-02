import { AlertTriangle } from "lucide-react"

import { useHudUpdate } from "@/lib/hudState"

/**
 * Renders one badge per active qblib QB.status effect (e.g. "bleeding",
 * "limping", a drug's "high_weed"). Deliberately generic -- qbhud has no
 * dependency on, and no business knowing about, whichever job/drug resource
 * registered a given effect name, so this can't hardcode per-effect icons or
 * colors the way a screen vignette or ptfx (owned by that effect's own
 * `fx`/`anim` definition, played back by QB.status itself) can. A humanized
 * label plus severity, if the effect uses one, is the most this component
 * can honestly show.
 *
 * Always rendered when effects are active -- unlike mic/cash/bank/etc, this
 * isn't behind a Config.hud.elements toggle, matching health/armour/job/gang
 * staying ungated (dynamic mode only suppresses neutral gauges; see
 * config.lua's own comment).
 */
function humanize(name: string): string {
    return name
        .replace(/[_-]+/g, " ")
        .replace(/\b\w/g, (c) => c.toUpperCase())
}

export function StatusEffects() {
    const update = useHudUpdate()
    if (!update.status || update.status.length === 0) return null

    return (
        <div className="flex flex-col items-end gap-1.5">
            {update.status.map((effect) => (
                <div
                    key={effect.name}
                    className="hud-panel flex items-center gap-2 rounded-full py-1.5 pl-2 pr-3.5 overlay-text"
                    title={humanize(effect.name)}
                >
                    <span className="icon-badge icon-badge-destructive">
                        <AlertTriangle className="h-3.5 w-3.5" aria-hidden />
                    </span>
                    <span className="text-xs font-medium">
                        {humanize(effect.name)}
                        {effect.severity != null ? ` · ${effect.severity}` : ""}
                    </span>
                </div>
            ))}
        </div>
    )
}
