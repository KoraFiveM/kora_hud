import { Droplets, Utensils } from "lucide-react"

import { useHudState } from "@/lib/hudState"
import { StatBar } from "./StatBar"

export function HungerThirst() {
    const { config, update } = useHudState()
    if (!config.elements.hungerThirst) return null

    return (
        <div className="hud-chip flex flex-col gap-1.5 px-3 py-2">
            <StatBar icon={Utensils} value={update.hunger} colorClassName="bg-success" label="Hunger" />
            <StatBar icon={Droplets} value={update.thirst} colorClassName="bg-info" label="Thirst" />
        </div>
    )
}
