import { Brain } from "lucide-react"

import { useHudConfig, useHudUpdate, useLocale } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

// Stress is bad when *high* -- invert the banding so a full ring reads red,
// not green, unlike every other vital.
export function Stress() {
    const t = useLocale()
    const config = useHudConfig()
    const update = useHudUpdate()
    if (!config.elements.stress) return null

    return <RadialGauge icon={Brain} value={update.stress} defaultValue={0} label={t("UI.stress")} color={statColor(update.stress, true)} pulse />
}
