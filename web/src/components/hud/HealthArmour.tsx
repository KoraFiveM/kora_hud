import { Heart, Shield } from "lucide-react"

import { useHudState } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

// GTA's death floor is commonly 100, not 0 (see qblib's modules/cache
// docs.md) -- display health relative to that floor so an empty bar means
// "close to death", not "at some arbitrary engine minimum".
const HEALTH_FLOOR = 100
const HEALTH_CEILING = 200

// Baseline "usual player data" -- always rendered, not config-toggleable.
export function HealthArmour() {
    const { update } = useHudState()
    const healthPercent = ((update.health - HEALTH_FLOOR) / (HEALTH_CEILING - HEALTH_FLOOR)) * 100

    return (
        <div className="flex items-center gap-2">
            <RadialGauge icon={Heart} value={healthPercent} label="Health" color={statColor(healthPercent)} pulse />
            <RadialGauge icon={Shield} value={update.armour} label="Armour" color={statColor(update.armour)} />
        </div>
    )
}
