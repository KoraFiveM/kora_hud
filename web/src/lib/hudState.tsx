import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react"

import { fetchNui } from "./fetchNui"
import type {
    HudConfigPayload,
    HudLayoutModePayload,
    HudLayoutOffset,
    HudLayoutResetPayload,
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
    // Both of these mirror config.lua's shipped defaults for the same reason
    // as vitalsInterval: this is the state the HUD renders in before
    // "qbhud:config" arrives, and in a plain browser (`pnpm dev`) where it
    // never does. Cash/bank side by side and an unmoved layout are the
    // pre-existing behaviour, so defaulting to them means the pre-config
    // window looks like the HUD rather than like a different one.
    money: { scrollAccounts: false, scrollAccountsTime: 5000 },
    layout: { movable: true, command: "hudlayout", offsets: {} },
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

/**
 * The layout editor's whole state, assembled from three different sources --
 * Config.layout (a "qbhud:config" message), the editor toggle
 * ("qbhud:layoutMode"), and the offsets the page is currently holding -- so
 * every movable section reads one value instead of three.
 */
export interface HudLayoutState {
    /** Config.layout.movable. False means sections are never draggable. */
    movable: boolean
    /** Config.layout.command, shown in the editor hint so it isn't hardcoded twice. */
    command: string
    /** Whether the player has the editor open (Lua holds NUI focus while true). */
    editing: boolean
    offsets: Record<string, HudLayoutOffset>
    /**
     * Called once per finished drag with that section's new offset. Updates
     * the page and persists the FULL map through Lua -- the NUI holds no
     * authority over any of this, it just reports where the player dropped
     * the section.
     */
    commitOffset: (section: string, offset: HudLayoutOffset) => void
}

const DEFAULT_LAYOUT: HudLayoutState = {
    movable: true,
    command: "hudlayout",
    editing: false,
    offsets: {},
    commitOffset: () => {},
}

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
const HudLayoutContext = createContext<HudLayoutState>(DEFAULT_LAYOUT)

/**
 * Single subscription point for "qbhud:config", "qbhud:vitals",
 * "qbhud:update", "qbhud:vehicle", "qbhud:visibility", "qbhud:layoutMode" and
 * "qbhud:layoutReset" -- every HUD element reads its own slice through the
 * hooks below instead of each independently subscribing to the wire messages,
 * so client/hud.lua's payloads have exactly one consumer-side entry point.
 *
 * It is also the only place that posts BACK to Lua ("qbhud:ready" and
 * "qbhud:saveLayout"), for the same reason.
 */
export function HudStateProvider({ children }: { children: ReactNode }) {
    const [config, setConfig] = useState<HudConfigPayload>(DEFAULT_CONFIG)
    const [vitals, setVitals] = useState<HudVitalsPayload>(DEFAULT_VITALS)
    const [update, setUpdate] = useState<HudUpdatePayload>(DEFAULT_UPDATE)
    const [vehicle, setVehicle] = useState<HudVehiclePayload>(DEFAULT_VEHICLE)
    const [visible, setVisible] = useState<boolean>(DEFAULT_VISIBLE)
    const [layoutEditing, setLayoutEditing] = useState(false)
    const [offsets, setOffsets] = useState<Record<string, HudLayoutOffset>>(DEFAULT_LAYOUT.offsets)

    // Mirrors `offsets` for the callbacks below, which run from a mouseup
    // listener and from a wire handler rather than from a render -- both need
    // the CURRENT map to build the next one, and neither can read it out of a
    // closure without pinning whatever it was when that closure was made.
    const offsetsRef = useRef(offsets)
    // True from the moment a drag is committed until Lua has acknowledged the
    // matching save. See the "qbhud:layoutMode" handler for what it's for.
    const unsavedRef = useRef(false)

    const applyOffsets = useCallback((next: Record<string, HudLayoutOffset>) => {
        offsetsRef.current = next
        setOffsets(next)
    }, [])

    // Fire-and-forget on purpose: this is presentation geometry, and Lua
    // re-validates and clamps every value before it reaches KVP (see
    // client/hud.lua's writeLayout), so there is nothing in the response for
    // the page to apply -- the layout it already rendered IS the answer.
    const saveOffsets = useCallback((next: Record<string, HudLayoutOffset>) => {
        unsavedRef.current = true
        fetchNui("qbhud:saveLayout", next)
            .then(() => {
                unsavedRef.current = false
            })
            .catch((error) => {
                console.error("[qbhud] qbhud:saveLayout failed:", error)
            })
    }, [])

    // The WHOLE map goes over, not just the section that moved: Lua stores
    // one JSON blob per player and overwrites it outright, so a partial
    // submission would delete every other section's saved position.
    const commitOffset = useCallback(
        (section: string, offset: HudLayoutOffset) => {
            const next = { ...offsetsRef.current, [section]: offset }
            applyOffsets(next)
            saveOffsets(next)
        },
        [applyOffsets, saveOffsets],
    )

    useNuiEvent<HudConfigPayload>("qbhud:config", (payload) => {
        if (!payload) return
        setConfig(payload)
        // Config only ever arrives on resource start or in answer to the ready
        // ping below -- i.e. at a point where this page holds no layout state
        // worth keeping -- so taking Lua's KVP-backed offsets verbatim here
        // can't discard a move the player has just made.
        const seeded = payload.layout?.offsets
        applyOffsets(seeded && typeof seeded === "object" ? seeded : {})
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

    useNuiEvent<HudLayoutModePayload>("qbhud:layoutMode", (payload) => {
        if (typeof payload !== "boolean") return
        setLayoutEditing(payload)
        // Second chance at the save, not a duplicate of it: the drag-end post
        // is fire-and-forget, so one that failed (or that the player closed
        // the editor on top of) would otherwise lose the move without saying
        // so. Closing the editor is the last moment the page can resend, and
        // re-sending an already-stored layout is a no-op in Lua.
        if (!payload && unsavedRef.current) saveOffsets(offsetsRef.current)
    })

    useNuiEvent<HudLayoutResetPayload>("qbhud:layoutReset", () => {
        // Lua has already deleted the KVP key, so this deliberately does NOT
        // post anything back -- it only drops what the page is holding, which
        // leaving edit mode does not do. Ignores the payload value: the
        // message arriving at all is the event.
        unsavedRef.current = false
        applyOffsets({})
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

    // The one context value that IS an assembled object rather than a raw
    // channel payload, because it has no single channel of its own. Safe
    // where the four data channels wouldn't be: its inputs are a config
    // message, an editor toggle and a finished drag, so it changes a handful
    // of times per session instead of ten times a second.
    const layout = useMemo<HudLayoutState>(
        () => ({
            movable: config.layout?.movable !== false,
            command: config.layout?.command ?? DEFAULT_LAYOUT.command,
            editing: layoutEditing,
            offsets,
            commitOffset,
        }),
        [config.layout, layoutEditing, offsets, commitOffset],
    )

    // Each provider is handed the state value itself -- no useMemo wrapper
    // object to build, and nothing that changes identity unless that specific
    // channel's own message arrived.
    return (
        <HudConfigContext.Provider value={config}>
            <HudLayoutContext.Provider value={layout}>
                <HudVisibleContext.Provider value={visible}>
                    <HudVitalsContext.Provider value={vitals}>
                        <HudUpdateContext.Provider value={update}>
                            <HudVehicleContext.Provider value={vehicle}>{children}</HudVehicleContext.Provider>
                        </HudUpdateContext.Provider>
                    </HudVitalsContext.Provider>
                </HudVisibleContext.Provider>
            </HudLayoutContext.Provider>
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

/** Per-player section offsets and layout-editor state. */
export function useHudLayout() {
    return useContext(HudLayoutContext)
}
