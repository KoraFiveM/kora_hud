import { Zap } from "lucide-react"

import { useHudState } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

export function Stamina() {
    const { config, update } = useHudState()
    if (!config.elements.stamina) return null

    return <RadialGauge icon={Zap} value={update.stamina} defaultValue={100} label="Stamina" color={statColor(update.stamina)} />
}
