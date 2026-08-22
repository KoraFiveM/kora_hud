import { Zap } from "lucide-react"

import { useHudState } from "@/lib/hudState"
import { StatBar } from "./StatBar"

export function Stamina() {
    const { config, update } = useHudState()
    if (!config.elements.stamina) return null

    return (
        <div className="hud-chip px-3 py-2">
            <StatBar icon={Zap} value={update.stamina} colorClassName="bg-warning" label="Stamina" />
        </div>
    )
}
