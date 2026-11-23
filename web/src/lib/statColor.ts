// Shared healthy/warning/critical banding every vital's RadialGauge colors
// itself with. "Healthy" is the kora_theme primary colour, so the gauges
// follow whatever accent the server's theme uses. `invert` is for stats where
// *high* is bad (stress) instead of good (health/armour/stamina/hunger/
// thirst/fuel) -- so the band math runs against (100 - value) instead of value.
export function statColor(value: number, invert = false): string {
    const banded = invert ? 100 - value : value
    if (banded >= 60) return "hsl(var(--primary))"
    if (banded >= 30) return "hsl(var(--warning))"
    return "hsl(var(--destructive))"
}
