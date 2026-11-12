import { Zap } from "lucide-react"

import { useHudConfig, useHudVitals } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

export function Stamina() {
    const config = useHudConfig()
    const vitals = useHudVitals()
    if (!config.elements.stamina) return null

    return <RadialGauge icon={Zap} value={vitals.stamina} defaultValue={100} label="Stamina" color={statColor(vitals.stamina)} />
}
