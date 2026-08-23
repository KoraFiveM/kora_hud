import type { HudThemePayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

/**
 * Applies whatever tokens qb-hud's own client/hud.lua forwards from
 * QB.theme.tokens() (qblib) straight onto :root as CSS custom properties.
 * Deliberately no HSL math here -- that derivation happens once, in Lua, in
 * qblib's modules/theme -- this component only ever writes keys it's handed.
 * Compare qblib's own web/src/components/theme/ThemeSynchronizer.tsx, which
 * *computes* tokens; this one only *applies* them.
 */
export function HudThemeSynchronizer() {
    useNuiEvent<HudThemePayload>("qbhud:theme", (tokens) => {
        if (!tokens) return

        const root = document.documentElement.style
        for (const [key, value] of Object.entries(tokens)) {
            // A malformed theme payload could hand us a non-string value
            // (e.g. a number or nested object from a bad adapter) --
            // setProperty requires a string, so skip anything else rather
            // than throwing or injecting unexpected CSS.
            if (typeof value !== "string") continue
            root.setProperty(`--${key}`, value)
        }
    })

    return null
}
