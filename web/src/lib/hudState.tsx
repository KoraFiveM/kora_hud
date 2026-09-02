import { createContext, useContext, useEffect, useState, type ReactNode } from "react"

import { fetchNui } from "./fetchNui"
import type {
    HudConfigPayload,
    HudUpdatePayload,
    HudVehiclePayload,
    HudVisibilityPayload,
    HudVitalsPayload,
} from "./types"
import { useNuiEvent } from "./useNuiEvent"

const DEFAULT_CONFIG: HudConfigPayload = {
    dynamic: false,
    elements: {
        mic: true,
        cash: true,
        bank: true,
        hungerThirst: true,
        stamina: true,
        stress: true,
        vehicle: true,
    },
    // Matches client/hud.lua's own fallback, so the gauges animate correctly
    // even in the window before the first "qbhud:config" message lands.
    vitalsInterval: 150,
}

const DEFAULT_VITALS: HudVitalsPayload = {
    health: 200,
    maxHealth: 200,
    armour: 0,
    stamina: 100,
    talking: false,
}

const DEFAULT_UPDATE: HudUpdatePayload = {
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

// Hidden until Lua says otherwise: client/hud.lua sends "qbhud:visibility"
// synchronously on resource start regardless of adapter (true immediately for
// an adapter with no login concept, e.g. the stub), so this default only
// matters for the brief window before that first message arrives -- and
// hidden is the correct assumption for that window, not just a fallback,
// since "only show once logged in" must hold even during it.
const DEFAULT_VISIBLE = false

// One context PER CHANNEL rather than a single object holding all of them.
// React re-renders every consumer of a context whose value changed, so a
// combined `{ config, vitals, update, vehicle, visible }` value means one
// stamina tick -- ten a second for the whole length of a sprint -- re-renders
// the job panel, the money panel and the status list too, none of which can
// possibly have changed. Split, a vitals message re-renders exactly the
// health/armour/stamina/mic components that read it.
//
// This mirrors client/hud.lua's own split: the wire channels and the contexts
// are the same four cadences end to end.
const HudConfigContext = createContext<HudConfigPayload>(DEFAULT_CONFIG)
const HudVitalsContext = createContext<HudVitalsPayload>(DEFAULT_VITALS)
const HudUpdateContext = createContext<HudUpdatePayload>(DEFAULT_UPDATE)
const HudVehicleContext = createContext<HudVehiclePayload>(DEFAULT_VEHICLE)
const HudVisibleContext = createContext<boolean>(DEFAULT_VISIBLE)

/**
 * Single subscription point for "qbhud:config", "qbhud:vitals",
 * "qbhud:update", "qbhud:vehicle", and "qbhud:visibility" -- every HUD element
 * reads its own slice through the hooks below instead of each independently
 * subscribing to the wire messages, so client/hud.lua's payloads have exactly
 * one consumer-side entry point.
 */
export function HudStateProvider({ children }: { children: ReactNode }) {
    const [config, setConfig] = useState<HudConfigPayload>(DEFAULT_CONFIG)
    const [vitals, setVitals] = useState<HudVitalsPayload>(DEFAULT_VITALS)
    const [update, setUpdate] = useState<HudUpdatePayload>(DEFAULT_UPDATE)
    const [vehicle, setVehicle] = useState<HudVehiclePayload>(DEFAULT_VEHICLE)
    const [visible, setVisible] = useState<boolean>(DEFAULT_VISIBLE)

    useNuiEvent<HudConfigPayload>("qbhud:config", (payload) => {
        if (payload) setConfig(payload)
    })

    useNuiEvent<HudVitalsPayload>("qbhud:vitals", (payload) => {
        if (payload) setVitals(payload)
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

    // Each provider is handed the state value itself -- no useMemo wrapper
    // object to build, and nothing that changes identity unless that specific
    // channel's own message arrived.
    return (
        <HudConfigContext.Provider value={config}>
            <HudVisibleContext.Provider value={visible}>
                <HudVitalsContext.Provider value={vitals}>
                    <HudUpdateContext.Provider value={update}>
                        <HudVehicleContext.Provider value={vehicle}>{children}</HudVehicleContext.Provider>
                    </HudUpdateContext.Provider>
                </HudVitalsContext.Provider>
            </HudVisibleContext.Provider>
        </HudConfigContext.Provider>
    )
}

/** Element toggles and dynamic-gauge mode. Sent once, on resource start. */
export function useHudConfig() {
    return useContext(HudConfigContext)
}

/** Health/armour/stamina/talking -- the fast channel. */
export function useHudVitals() {
    return useContext(HudVitalsContext)
}

/** Job/gang/money/needs/status -- the framework-sourced, event-driven channel. */
export function useHudUpdate() {
    return useContext(HudUpdateContext)
}

/** Vehicle telemetry, or null on foot. */
export function useHudVehicle() {
    return useContext(HudVehicleContext)
}

/** Whether the HUD should render at all (login state and the show/hide exports). */
export function useHudVisible() {
    return useContext(HudVisibleContext)
}
