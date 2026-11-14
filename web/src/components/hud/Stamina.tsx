import { Zap } from "lucide-react"

import { useHudConfig, useHudVitals, useLocale } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

export function Stamina() {
    const t = useLocale()
    const config = useHudConfig()
    const vitals = useHudVitals()
    if (!config.elements.stamina) return null

    return <RadialGauge icon={Zap} value={vitals.stamina} defaultValue={100} label={t("UI.stamina")} color={statColor(vitals.stamina)} />
}
