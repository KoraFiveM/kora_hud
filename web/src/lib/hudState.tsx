import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react"

import { fetchNui } from "./fetchNui"
import type { HudConfigPayload, HudUpdatePayload, HudVehiclePayload, HudVisibilityPayload } from "./types"
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
    maxHealth: 200,
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
    status: [],
}

// "qbhud:vehicle" is sent independently of "qbhud:update" (see
// client/hud.lua's pushVehicleUpdate) so vehicle telemetry can refresh on its
// own faster cadence without dragging the rest of the HUD along with it.
const DEFAULT_VEHICLE: HudVehiclePayload = null

interface HudState {
    config: HudConfigPayload
    update: HudUpdatePayload
    vehicle: HudVehiclePayload
    visible: boolean
}

// Hidden until Lua says otherwise: client/hud.lua sends "qbhud:visibility"
// synchronously on resource start regardless of adapter (true immediately for
// an adapter with no login concept, e.g. the stub), so this default only
// matters for the brief window before that first message arrives -- and
// hidden is the correct assumption for that window, not just a fallback,
// since "only show once logged in" must hold even during it.
const DEFAULT_VISIBLE = false

const HudStateContext = createContext<HudState>({
    config: DEFAULT_CONFIG,
    update: DEFAULT_UPDATE,
    vehicle: DEFAULT_VEHICLE,
    visible: DEFAULT_VISIBLE,
})

/**
 * Single subscription point for "qbhud:config", "qbhud:update",
 * "qbhud:vehicle", and "qbhud:visibility" -- every HUD element reads its own
 * slice from this context instead of each independently subscribing to the
 * wire messages, so client/hud.lua's payloads have exactly one consumer-side
 * entry point.
 */
export function HudStateProvider({ children }: { children: ReactNode }) {
    const [config, setConfig] = useState<HudConfigPayload>(DEFAULT_CONFIG)
    const [update, setUpdate] = useState<HudUpdatePayload>(DEFAULT_UPDATE)
    const [vehicle, setVehicle] = useState<HudVehiclePayload>(DEFAULT_VEHICLE)
    const [visible, setVisible] = useState<boolean>(DEFAULT_VISIBLE)

    useNuiEvent<HudConfigPayload>("qbhud:config", (payload) => {
        if (payload) setConfig(payload)
    })

    useNuiEvent<HudUpdatePayload>("qbhud:update", (payload) => {
        if (payload) setUpdate(payload)
    })

    // Unlike the other handlers, `payload` legitimately being `null` (on
    // foot) is a real state, not a "message dropped" signal -- so this
    // doesn't gate on truthiness the way qbhud:config/qbhud:update do.
    useNuiEvent<HudVehiclePayload>("qbhud:vehicle", (payload) => {
        setVehicle(payload ?? null)
    })

    useNuiEvent<HudVisibilityPayload>("qbhud:visibility", (payload) => {
        if (typeof payload === "boolean") setVisible(payload)
    })

    // client/hud.lua's resource-start SendNUIMessage calls are best-effort --
    // FiveM drops them if this page hasn't mounted (and attached its
    // "message" listener) yet, which is common for a player already logged
    // in when qbhud (re)starts. This ping is the guaranteed half of the fix:
    // once mounted, ask Lua for a fresh push instead of hoping the first one
    // landed. See client/hud.lua's "qbhud:ready" callback for the other half.
    useEffect(() => {
        fetchNui("qbhud:ready").catch((error) => {
            console.error("[qbhud] qbhud:ready ping failed:", error)
        })
    }, [])

    const value = useMemo(() => ({ config, update, vehicle, visible }), [config, update, vehicle, visible])

    return <HudStateContext.Provider value={value}>{children}</HudStateContext.Provider>
}

export function useHudState() {
    return useContext(HudStateContext)
}
