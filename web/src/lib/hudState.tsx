import { createContext, useContext, useState, type ReactNode } from "react"

import type { HudConfigPayload, HudUpdatePayload, HudVisibilityPayload } from "./types"
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
    visible: boolean
}

// Hidden until Lua says otherwise: client/hud.lua sends "qbhud:visibility"
// synchronously on resource start regardless of adapter (true immediately for
// an adapter with no login concept, e.g. the stub), so this default only
// matters for the brief window before that first message arrives -- and
// hidden is the correct assumption for that window, not just a fallback,
// since "only show once logged in" must hold even during it.
const DEFAULT_VISIBLE = false

const HudStateContext = createContext<HudState>({ config: DEFAULT_CONFIG, update: DEFAULT_UPDATE, visible: DEFAULT_VISIBLE })

/**
 * Single subscription point for "qbhud:config", "qbhud:update", and
 * "qbhud:visibility" -- every HUD element reads its own slice from this
 * context instead of each independently subscribing to the wire messages, so
 * client/hud.lua's one consolidated payload per tick has exactly one
 * consumer-side entry point.
 */
export function HudStateProvider({ children }: { children: ReactNode }) {
    const [config, setConfig] = useState<HudConfigPayload>(DEFAULT_CONFIG)
    const [update, setUpdate] = useState<HudUpdatePayload>(DEFAULT_UPDATE)
    const [visible, setVisible] = useState<boolean>(DEFAULT_VISIBLE)

    useNuiEvent<HudConfigPayload>("qbhud:config", (payload) => {
        if (payload) setConfig(payload)
    })

    useNuiEvent<HudUpdatePayload>("qbhud:update", (payload) => {
        if (payload) setUpdate(payload)
    })

    useNuiEvent<HudVisibilityPayload>("qbhud:visibility", (payload) => {
        if (typeof payload === "boolean") setVisible(payload)
    })

    return <HudStateContext.Provider value={{ config, update, visible }}>{children}</HudStateContext.Provider>
}

export function useHudState() {
    return useContext(HudStateContext)
}
