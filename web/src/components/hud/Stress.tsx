import { useHudConfig, useHudUpdate, useLocale } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"
import { useGaugeIcon } from "./gaugeIcons"

// Stress is bad when *high* -- invert the banding so a full ring reads red,
// not green, unlike every other vital.
export function Stress() {
    const t = useLocale()
    const icon = useGaugeIcon()
    const config = useHudConfig()
    const update = useHudUpdate()
    if (!config.elements.stress) return null

    return <RadialGauge icon={icon("stress")} value={update.stress} defaultValue={0} label={t("UI.stress")} color={statColor(update.stress, true)} pulse />
}
