import { useHudConfig, useHudVitals, useLocale } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"
import { useGaugeIcon } from "./gaugeIcons"

export function Stamina() {
    const t = useLocale()
    const icon = useGaugeIcon()
    const config = useHudConfig()
    const vitals = useHudVitals()
    if (!config.elements.stamina) return null

    return <RadialGauge icon={icon("stamina")} value={vitals.stamina} defaultValue={100} label={t("UI.stamina")} color={statColor(vitals.stamina)} />
}
