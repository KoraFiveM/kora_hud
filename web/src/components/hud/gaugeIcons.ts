import {
    Activity, Apple, Brain, CloudLightning, Cross, Droplet, Droplets, Footprints, Frown,
    GlassWater, Heart, HeartPulse, Sandwich, Shield, ShieldCheck, ShieldPlus, Utensils, Zap,
    type LucideIcon,
} from "lucide-react"

import { useHudLayout } from "@/lib/hudState"

const defaults = {
    health: Heart,
    armour: Shield,
    stamina: Zap,
    hunger: Utensils,
    thirst: Droplets,
    stress: Brain,
}

const alternatives = new Map<string, LucideIcon>([
    ["heartPulse", HeartPulse], ["cross", Cross],
    ["shieldCheck", ShieldCheck], ["shieldPlus", ShieldPlus],
    ["footprints", Footprints], ["activity", Activity],
    ["sandwich", Sandwich], ["apple", Apple],
    ["droplet", Droplet], ["glassWater", GlassWater],
    ["frown", Frown], ["cloudLightning", CloudLightning],
])

export function useGaugeIcon() {
    const settings = useHudLayout().settings.gauges
    return (vital: keyof typeof defaults): LucideIcon => {
        const choice = settings?.[`${vital}Icon`]
        return (typeof choice === "string" ? alternatives.get(choice) : undefined) ?? defaults[vital]
    }
}
