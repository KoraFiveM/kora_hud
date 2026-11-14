import { Droplets, Utensils } from "lucide-react"

import { useHudConfig, useHudUpdate, useLocale } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

export function HungerThirst() {
    const t = useLocale()
    const config = useHudConfig()
    const update = useHudUpdate()
    if (!config.elements.hungerThirst) return null

    return (
        <div className="flex items-center gap-2">
            <RadialGauge icon={Utensils} value={update.hunger} defaultValue={100} label={t("UI.hunger")} color={statColor(update.hunger)} />
            <RadialGauge icon={Droplets} value={update.thirst} defaultValue={100} label={t("UI.thirst")} color={statColor(update.thirst)} />
        </div>
    )
}
