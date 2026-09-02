import { Heart, Shield } from "lucide-react"

import { useHudVitals } from "@/lib/hudState"
import { statColor } from "@/lib/statColor"
import { RadialGauge } from "./RadialGauge"

// GTA's death floor is commonly 100, not 0 (see qblib's modules/cache
// docs.md) -- display health relative to that floor so an empty bar means
// "close to death", not "at some arbitrary engine minimum".
const HEALTH_FLOOR = 100

// Baseline "usual player data" -- not independently toggleable. Dynamic mode
// can still hide either gauge while it is at its neutral value.
export function HealthArmour() {
    const vitals = useHudVitals()
    // GTA reports a ped's health on a native scale where 100 is the death
    // floor. Freemode male and female peds have different maximums (normally
    // 200 and 175 respectively), so Lua sends the current ped's actual max.
    const maxHealth = Math.max(HEALTH_FLOOR + 1, vitals.maxHealth)
    const healthPercent = ((vitals.health - HEALTH_FLOOR) / (maxHealth - HEALTH_FLOOR)) * 100

    return (
        <div className="flex items-center gap-2">
            <RadialGauge icon={Heart} value={healthPercent} defaultValue={100} label="Health" color={statColor(healthPercent)} pulse />
            <RadialGauge icon={Shield} value={vitals.armour} defaultValue={0} label="Armour" color="hsl(var(--armour))" />
        </div>
    )
}
