import { createContext, useContext, useState, type ReactNode } from "react"

import type { HudConfigPayload, HudUpdatePayload } from "./types"
import { useNuiEvent } from "./useNuiEvent"

const DEFAULT_CONFIG: HudConfigPayload = {
    elements: {
        mic: true,
        cash: true,
        bank: true,
        hungerThirst: true,
        stamina: true,
        stress: true,
        vehicle: true,
    },
}

const DEFAULT_UPDATE: HudUpdatePayload = {
    health: 200,
    armour: 0,
    stamina: 100,
    talking: false,
    job: { name: "unemployed", label: "Civilian", grade: 0, gradeLabel: "Civilian", onDuty: false },
    gang: null,
    cash: 0,
    bank: 0,
    hunger: 100,
    thirst: 100,
    stress: 0,
    vehicle: null,
}

interface HudState {
    config: HudConfigPayload
    update: HudUpdatePayload
}

const HudStateContext = createContext<HudState>({ config: DEFAULT_CONFIG, update: DEFAULT_UPDATE })

/**
 * Single subscription point for both "qbhud:config" and "qbhud:update" --
 * every HUD element reads its own slice from this context instead of each
 * independently subscribing to the wire messages, so client/hud.lua's one
 * consolidated payload per tick has exactly one consumer-side entry point.
 */
export function HudStateProvider({ children }: { children: ReactNode }) {
    const [config, setConfig] = useState<HudConfigPayload>(DEFAULT_CONFIG)
    const [update, setUpdate] = useState<HudUpdatePayload>(DEFAULT_UPDATE)

    useNuiEvent<HudConfigPayload>("qbhud:config", (payload) => {
        if (payload) setConfig(payload)
    })

    useNuiEvent<HudUpdatePayload>("qbhud:update", (payload) => {
        if (payload) setUpdate(payload)
    })

    return <HudStateContext.Provider value={{ config, update }}>{children}</HudStateContext.Provider>
}

export function useHudState() {
    return useContext(HudStateContext)
}
