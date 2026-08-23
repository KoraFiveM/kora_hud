import { AlertTriangle } from "lucide-react"

import { useHudState } from "@/lib/hudState"

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
 * staying ungated (see config.lua's own comment on why).
 */
function humanize(name: string): string {
    return name
        .replace(/[_-]+/g, " ")
        .replace(/\b\w/g, (c) => c.toUpperCase())
}

export function StatusEffects() {
    const { update } = useHudState()
    if (!update.status || update.status.length === 0) return null

    return (
        <div className="flex flex-col gap-1">
            {update.status.map((effect) => (
                <div key={effect.name} className="hud-chip flex items-center gap-2 px-3 py-1.5" title={humanize(effect.name)}>
                    <AlertTriangle className="size-4 text-destructive" />
                    <span className="text-sm">
                        {humanize(effect.name)}
                        {effect.severity != null ? ` (${effect.severity})` : ""}
                    </span>
                </div>
            ))}
        </div>
    )
}
