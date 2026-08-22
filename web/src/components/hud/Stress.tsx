import { Brain } from "lucide-react"

import { useHudState } from "@/lib/hudState"
import { StatBar } from "./StatBar"

export function Stress() {
    const { config, update } = useHudState()
    if (!config.elements.stress) return null

    return (
        <div className="hud-chip px-3 py-2">
            <StatBar icon={Brain} value={update.stress} colorClassName="bg-destructive" label="Stress" />
        </div>
    )
}
