import { useHudConfig, useHudUpdate, useLocale } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"
import { useGaugeIcon } from "./gaugeIcons"

export function HungerThirst() {
    const t = useLocale()
    const icon = useGaugeIcon()
    const config = useHudConfig()
    const update = useHudUpdate()
    if (!config.elements.hungerThirst) return null

    return (
        <div className="flex items-center gap-2">
            <RadialGauge icon={icon("hunger")} value={update.hunger} defaultValue={100} label={t("UI.hunger")} color={statColor(update.hunger)} />
            <RadialGauge icon={icon("thirst")} value={update.thirst} defaultValue={100} label={t("UI.thirst")} color={statColor(update.thirst)} />
        </div>
    )
}
