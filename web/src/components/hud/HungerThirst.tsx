import { Droplets, Utensils } from "lucide-react"

import { useHudState } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

export function HungerThirst() {
    const { config, update } = useHudState()
    if (!config.elements.hungerThirst) return null

    return (
        <div className="flex items-center gap-2">
            <RadialGauge icon={Utensils} value={update.hunger} defaultValue={100} label="Hunger" color={statColor(update.hunger)} />
            <RadialGauge icon={Droplets} value={update.thirst} defaultValue={100} label="Thirst" color={statColor(update.thirst)} />
        </div>
    )
}
