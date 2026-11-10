import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react"

import { fetchNui } from "./fetchNui"
import type {
    HudConfigPayload,
    HudEditorConfig,
    HudLayoutModePayload,
    HudLayoutOffset,
    HudLayoutResetPayload,
    HudPlayerIdPayload,
    HudUpdatePayload,
    HudVehiclePayload,
    HudVisibilityPayload,
    HudVitalsPayload,
    UiElementDef,
    UiElementsPayload,
    UiSettingValue,
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
    speedUnit: "kmh",
    // Matches client/hud.lua's own fallback, so the gauges animate correctly
    // even in the window before the first "kora_hud:config" message lands.
    vitalsInterval: 150,
    // Both of these mirror config.lua's shipped defaults for the same reason
    // as vitalsInterval: this is the state the HUD renders in before
    // "kora_hud:config" arrives, and in a plain browser (`pnpm dev`) where it
    // never does. Cash/bank side by side and an unmoved layout are the
    // pre-existing behaviour, so defaulting to them means the pre-config
    // window looks like the HUD rather than like a different one.
    money: { scrollAccounts: false, scrollAccountsTime: 5000 },
    layout: {
        movable: true,
        command: "hudlayout",
        offsets: {},
        scales: {},
        justifications: {},
        gaugesBottomAnchored: true,
        minimapVehicleOnly: false,
        minimapVehicleOnlyDefault: false,
        minimapVehicleOnlyAllowed: true,
    },
}

const DEFAULT_VITALS: HudVitalsPayload = {
    health: 200,
    maxHealth: 200,
    armour: 0,
    stamina: 100,
    talking: false,
    voiceMode: null,
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

// "kora_hud:vehicle" is sent independently of "kora_hud:update" (see
// client/hud.lua's pushVehicleUpdate) so vehicle telemetry can refresh on its
// own faster cadence without dragging the rest of the HUD along with it.
const DEFAULT_VEHICLE: HudVehiclePayload = null
const DEFAULT_PLAYER_ID: HudPlayerIdPayload = null

// Hidden until Lua says otherwise: client/hud.lua sends "kora_hud:visibility"
// synchronously on resource start regardless of adapter (true immediately for
// an adapter with no login concept, e.g. the stub), so this default only
// matters for the brief window before that first message arrives -- and
// hidden is the correct assumption for that window, not just a fallback,
// since "only show once logged in" must hold even during it.
const DEFAULT_VISIBLE = false

/**
 * The layout editor's whole state, assembled from three different sources --
 * Config.layout (a "kora_hud:config" message), the editor toggle
 * ("kora_hud:layoutMode"), and the offsets the page is currently holding -- so
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
    scales: Record<string, number>
    justifications: Record<string, "left" | "center" | "right">
    /** Whether gauges share the bottom anchor with the vehicle panel. */
    gaugesBottomAnchored: boolean
    /** This player's "Minimap only in vehicle" choice (the preview while editing). */
    minimapVehicleOnly: boolean
    /** False when the server forces its default, which hides the switch. */
    minimapVehicleOnlyAllowed: boolean
    /**
     * Called once per finished drag with that section's new offset. Updates
     * the page preview only; the NUI holds no authority over persistence until
     * the player explicitly confirms the complete layout.
     */
    commitOffset: (section: string, offset: HudLayoutOffset) => void
    /** Preview a section's scale until the player confirms the layout. */
    commitScale: (section: string, scale: number) => void
    /** Preview alignment of a component's contents until confirmation. */
    commitJustification: (section: string, justification: "left" | "center" | "right") => void
    /** Preview the gauges' bottom-anchor preference until confirmation. */
    setGaugesBottomAnchored: (bottomAnchored: boolean) => void
    /** Preview the minimap-only-in-vehicle preference until confirmation. */
    setMinimapVehicleOnly: (vehicleOnly: boolean) => void
    /** Preview the shipped layout until the player confirms it. */
    resetToDefaults: () => void
    /** /ui editor switches (enabled=false renders the classic editor). */
    editor: HudEditorConfig
    /** Elements hidden by this player (draft while editing). */
    hidden: Record<string, boolean>
    /** Per-element settings (draft while editing). */
    settings: Record<string, Record<string, UiSettingValue>>
    /** Elements registered by other resources, plus the minimap. */
    elements: UiElementDef[]
    /** The element picked in the editor panel (highlighted on screen). */
    selected: string | null
    select: (id: string | null) => void
    setHidden: (id: string, hidden: boolean) => void
    setSetting: (id: string, key: string, value: UiSettingValue) => void
    /** Puts one element back to its defaults (draft until Save). */
    resetElement: (id: string) => void
    /**
     * Tells the owner of a registered element where it currently is in the
     * draft, so its real element follows the proxy. `final` marks a drop or a
     * committed change (the minimap only re-applies on those); otherwise the
     * call is throttled to editor.previewInterval.
     */
    preview: (id: string, final: boolean, override?: Partial<UiPreviewEntry>) => void
    /** Persist the preview and leave edit mode. */
    confirm: () => void
    /** Restore the positions from when editing began and leave edit mode. */
    cancel: () => void
}

export interface UiPreviewEntry {
    x: number
    y: number
    scale: number
    hidden: boolean
    settings: Record<string, UiSettingValue>
}

const DEFAULT_EDITOR: HudEditorConfig = { enabled: false, allowHide: false, command: "hudlayout", previewInterval: 100 }

/** Lua encodes an empty table as `[]`; treat anything but a plain object as empty. */
function asRecord<T>(value: unknown): Record<string, T> {
    return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, T>) : {}
}

function without<T>(record: Record<string, T>, key: string): Record<string, T> {
    if (!(key in record)) return record
    const next = { ...record }
    delete next[key]
    return next
}

const DEFAULT_LAYOUT: HudLayoutState = {
    movable: true,
    command: "hudlayout",
    editing: false,
    offsets: {},
    scales: {},
    justifications: {},
    gaugesBottomAnchored: true,
    minimapVehicleOnly: false,
    minimapVehicleOnlyAllowed: true,
    commitOffset: () => {},
    commitScale: () => {},
    commitJustification: () => {},
    setGaugesBottomAnchored: () => {},
    setMinimapVehicleOnly: () => {},
    resetToDefaults: () => {},
    editor: DEFAULT_EDITOR,
    hidden: {},
    settings: {},
    elements: [],
    selected: null,
    select: () => {},
    setHidden: () => {},
    setSetting: () => {},
    resetElement: () => {},
    preview: () => {},
    confirm: () => {},
    cancel: () => {},
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
const HudPlayerIdContext = createContext<HudPlayerIdPayload>(DEFAULT_PLAYER_ID)
const HudVisibleContext = createContext<boolean>(DEFAULT_VISIBLE)
const HudLayoutContext = createContext<HudLayoutState>(DEFAULT_LAYOUT)

/**
 * Single subscription point for "kora_hud:config", "kora_hud:vitals",
 * "kora_hud:update", "kora_hud:vehicle", "kora_hud:visibility", "kora_hud:layoutMode" and
 * "kora_hud:layoutReset" -- every HUD element reads its own slice through the
 * hooks below instead of each independently subscribing to the wire messages,
 * so client/hud.lua's payloads have exactly one consumer-side entry point.
 *
 * It is also the only place that posts BACK to Lua ("kora_hud:ready" and
 * "kora_hud:finishLayout"), for the same reason.
 */
export function HudStateProvider({ children }: { children: ReactNode }) {
    const [config, setConfig] = useState<HudConfigPayload>(DEFAULT_CONFIG)
    const [vitals, setVitals] = useState<HudVitalsPayload>(DEFAULT_VITALS)
    const [update, setUpdate] = useState<HudUpdatePayload>(DEFAULT_UPDATE)
    const [vehicle, setVehicle] = useState<HudVehiclePayload>(DEFAULT_VEHICLE)
    const [playerId, setPlayerId] = useState<HudPlayerIdPayload>(DEFAULT_PLAYER_ID)
    const [visible, setVisible] = useState<boolean>(DEFAULT_VISIBLE)
    const [layoutEditing, setLayoutEditing] = useState(false)
    const [offsets, setOffsets] = useState<Record<string, HudLayoutOffset>>(DEFAULT_LAYOUT.offsets)
    const [scales, setScales] = useState<Record<string, number>>(DEFAULT_LAYOUT.scales)
    const [justifications, setJustifications] = useState<Record<string, "left" | "center" | "right">>(DEFAULT_LAYOUT.justifications)
    const [gaugesBottomAnchored, setGaugesBottomAnchoredState] = useState(DEFAULT_LAYOUT.gaugesBottomAnchored)
    const [minimapVehicleOnly, setMinimapVehicleOnlyState] = useState(DEFAULT_LAYOUT.minimapVehicleOnly)
    const [hidden, setHiddenState] = useState<Record<string, boolean>>({})
    const [settings, setSettingsState] = useState<Record<string, Record<string, UiSettingValue>>>({})
    const [elements, setElements] = useState<UiElementDef[]>([])
    const [selected, setSelected] = useState<string | null>(null)

    // Mirrors `offsets` for the callbacks below, which run from a mouseup
    // listener and from a wire handler rather than from a render -- both need
    // the CURRENT map to build the next one, and neither can read it out of a
    // closure without pinning whatever it was when that closure was made.
    const offsetsRef = useRef(offsets)
    // Snapshot taken on entry. Dragging only changes the preview; Cancel puts
    // this exact map back, while Confirm sends the current map to Lua once.
    const initialOffsetsRef = useRef<Record<string, HudLayoutOffset>>(DEFAULT_LAYOUT.offsets)
    const scalesRef = useRef(scales)
    const initialScalesRef = useRef<Record<string, number>>(DEFAULT_LAYOUT.scales)
    const justificationsRef = useRef(justifications)
    const initialJustificationsRef = useRef<Record<string, "left" | "center" | "right">>(DEFAULT_LAYOUT.justifications)
    const gaugesBottomAnchoredRef = useRef(gaugesBottomAnchored)
    const initialGaugesBottomAnchoredRef = useRef(DEFAULT_LAYOUT.gaugesBottomAnchored)
    const minimapVehicleOnlyRef = useRef(minimapVehicleOnly)
    const initialMinimapVehicleOnlyRef = useRef(DEFAULT_LAYOUT.minimapVehicleOnly)
    // What /hudlayoutreset and the editor's reset button return to. Lua sends it
    // with the config (Config.hud.minimapVehicleOnly.default).
    const minimapVehicleOnlyDefaultRef = useRef(false)
    const hiddenRef = useRef(hidden)
    const initialHiddenRef = useRef<Record<string, boolean>>({})
    const settingsRef = useRef(settings)
    const initialSettingsRef = useRef<Record<string, Record<string, UiSettingValue>>>({})
    const elementsRef = useRef(elements)
    elementsRef.current = elements
    const previewIntervalRef = useRef(DEFAULT_EDITOR.previewInterval)
    const lastPreviewRef = useRef<Record<string, number>>({})
    const pendingPreviewRef = useRef<Record<string, number>>({})

    const applyOffsets = useCallback((next: Record<string, HudLayoutOffset>) => {
        offsetsRef.current = next
        setOffsets(next)
    }, [])

    const commitOffset = useCallback(
        (section: string, offset: HudLayoutOffset) => {
            const next = { ...offsetsRef.current, [section]: offset }
            applyOffsets(next)
        },
        [applyOffsets],
    )

    const applyScales = useCallback((next: Record<string, number>) => {
        scalesRef.current = next
        setScales(next)
    }, [])

    const commitScale = useCallback(
        (section: string, scale: number) => applyScales({ ...scalesRef.current, [section]: scale }),
        [applyScales],
    )

    const applyJustifications = useCallback((next: Record<string, "left" | "center" | "right">) => {
        justificationsRef.current = next
        setJustifications(next)
    }, [])

    const commitJustification = useCallback(
        (section: string, justification: "left" | "center" | "right") =>
            applyJustifications({ ...justificationsRef.current, [section]: justification }),
        [applyJustifications],
    )

    const setGaugesBottomAnchored = useCallback((bottomAnchored: boolean) => {
        gaugesBottomAnchoredRef.current = bottomAnchored
        setGaugesBottomAnchoredState(bottomAnchored)
    }, [])

    const setMinimapVehicleOnly = useCallback((vehicleOnly: boolean) => {
        minimapVehicleOnlyRef.current = vehicleOnly
        setMinimapVehicleOnlyState(vehicleOnly)
    }, [])

    const applyHidden = useCallback((next: Record<string, boolean>) => {
        hiddenRef.current = next
        setHiddenState(next)
    }, [])

    const applySettings = useCallback((next: Record<string, Record<string, UiSettingValue>>) => {
        settingsRef.current = next
        setSettingsState(next)
    }, [])

    /** The draft entry an owner would receive for `id`. */
    const entryFor = useCallback((id: string, override?: Partial<UiPreviewEntry>): UiPreviewEntry => {
        const element = elementsRef.current.find((candidate) => candidate.id === id)
        const offset = offsetsRef.current[id] ?? element?.defaultOffset ?? { x: 0, y: 0 }
        return {
            x: offset.x,
            y: offset.y,
            scale: scalesRef.current[id] ?? 1,
            hidden: hiddenRef.current[id] === true,
            settings: settingsRef.current[id] ?? {},
            ...override,
        }
    }, [])

    const sendPreview = useCallback((id: string, final: boolean, override?: Partial<UiPreviewEntry>) => {
        lastPreviewRef.current[id] = Date.now()
        fetchNui("kora_hud:uiPreview", { final, elements: { [id]: entryFor(id, override) } }).catch((error) => {
            console.error("[kora_hud] kora_hud:uiPreview failed:", error)
        })
    }, [entryFor])

    const preview = useCallback((id: string, final: boolean, override?: Partial<UiPreviewEntry>) => {
        if (!elementsRef.current.some((element) => element.id === id)) return
        const pending = pendingPreviewRef.current[id]
        if (pending !== undefined) {
            window.clearTimeout(pending)
            delete pendingPreviewRef.current[id]
        }
        if (final) {
            sendPreview(id, true, override)
            return
        }
        // Leading edge, then at most one per interval; the trailing call
        // carries the latest position so a pause mid-drag still lands.
        const wait = previewIntervalRef.current - (Date.now() - (lastPreviewRef.current[id] ?? 0))
        if (wait <= 0) {
            sendPreview(id, false, override)
            return
        }
        pendingPreviewRef.current[id] = window.setTimeout(() => {
            delete pendingPreviewRef.current[id]
            sendPreview(id, false, override)
        }, wait)
    }, [sendPreview])

    const select = useCallback((id: string | null) => setSelected(id), [])

    const setHidden = useCallback((id: string, value: boolean) => {
        applyHidden(value ? { ...hiddenRef.current, [id]: true } : without(hiddenRef.current, id))
        preview(id, true)
    }, [applyHidden, preview])

    const setSetting = useCallback((id: string, key: string, value: UiSettingValue) => {
        applySettings({ ...settingsRef.current, [id]: { ...(settingsRef.current[id] ?? {}), [key]: value } })
        preview(id, true)
    }, [applySettings, preview])

    const resetElement = useCallback((id: string) => {
        applyOffsets(without(offsetsRef.current, id))
        applyScales(without(scalesRef.current, id))
        applyJustifications(without(justificationsRef.current, id))
        applyHidden(without(hiddenRef.current, id))
        applySettings(without(settingsRef.current, id))
        if (id === "gauges") setGaugesBottomAnchored(true)
        if (id === "minimap") setMinimapVehicleOnly(minimapVehicleOnlyDefaultRef.current)
        preview(id, true)
    }, [applyOffsets, applyScales, applyJustifications, applyHidden, applySettings, setGaugesBottomAnchored, setMinimapVehicleOnly, preview])

    const resetToDefaults = useCallback(() => {
        applyOffsets({})
        applyScales({})
        applyJustifications({})
        applyHidden({})
        applySettings({})
        setGaugesBottomAnchored(true)
        setMinimapVehicleOnly(minimapVehicleOnlyDefaultRef.current)
        for (const element of elementsRef.current) preview(element.id, true)
    }, [applyOffsets, applyScales, applyJustifications, applyHidden, applySettings, setGaugesBottomAnchored, setMinimapVehicleOnly, preview])

    const confirm = useCallback(() => {
        // The WHOLE map goes over: Lua stores one JSON blob per player and
        // overwrites it outright, so a partial submission would delete every
        // other section's saved position.
        fetchNui("kora_hud:finishLayout", {
            confirmed: true,
            offsets: offsetsRef.current,
            scales: scalesRef.current,
            justifications: justificationsRef.current,
            gaugesBottomAnchored: gaugesBottomAnchoredRef.current,
            minimapVehicleOnly: minimapVehicleOnlyRef.current,
            // The minimap's switch is the /minimap choice: always sent as a
            // boolean so "Reset all" also shows a hidden minimap again.
            hidden: elementsRef.current.some((element) => element.id === "minimap" && element.hideable)
                ? { ...hiddenRef.current, minimap: hiddenRef.current.minimap === true }
                : hiddenRef.current,
            settings: settingsRef.current,
        }).catch((error) => {
            console.error("[kora_hud] kora_hud:finishLayout failed:", error)
        })
    }, [])

    const cancel = useCallback(() => {
        fetchNui("kora_hud:finishLayout", { confirmed: false })
            .then(() => {
                applyOffsets(initialOffsetsRef.current)
                applyScales(initialScalesRef.current)
                applyJustifications(initialJustificationsRef.current)
                setGaugesBottomAnchored(initialGaugesBottomAnchoredRef.current)
                setMinimapVehicleOnly(initialMinimapVehicleOnlyRef.current)
                applyHidden(initialHiddenRef.current)
                applySettings(initialSettingsRef.current)
            })
            .catch((error) => {
                console.error("[kora_hud] kora_hud:finishLayout failed:", error)
            })
    }, [applyOffsets, applyScales, applyJustifications, applyHidden, applySettings, setGaugesBottomAnchored, setMinimapVehicleOnly])

    useNuiEvent<HudConfigPayload>("kora_hud:config", (payload) => {
        if (!payload) return
        setConfig(payload)
        // Config only ever arrives on resource start or in answer to the ready
        // ping below -- i.e. at a point where this page holds no layout state
        // worth keeping -- so taking Lua's KVP-backed offsets verbatim here
        // can't discard a move the player has just made.
        const seeded = payload.layout?.offsets
        applyOffsets(seeded && typeof seeded === "object" ? seeded : {})
        const seededScales = payload.layout?.scales
        applyScales(seededScales && typeof seededScales === "object" ? seededScales : {})
        const seededJustifications = payload.layout?.justifications
        applyJustifications(seededJustifications && typeof seededJustifications === "object" ? seededJustifications : {})
        setGaugesBottomAnchored(payload.layout?.gaugesBottomAnchored !== false)
        minimapVehicleOnlyDefaultRef.current = payload.layout?.minimapVehicleOnlyDefault === true
        setMinimapVehicleOnly(payload.layout?.minimapVehicleOnly === true)
        applyHidden(asRecord<boolean>(payload.layout?.hidden))
        applySettings(asRecord<Record<string, UiSettingValue>>(payload.layout?.settings))
        const interval = Number(payload.layout?.editor?.previewInterval)
        previewIntervalRef.current = Number.isFinite(interval) && interval >= 50 ? interval : DEFAULT_EDITOR.previewInterval
    })

    useNuiEvent<UiElementsPayload>("kora_hud:uiElements", (payload) => {
        setElements(Array.isArray(payload) ? payload.filter((element) => element && typeof element.id === "string" && element.rect) : [])
    })

    useNuiEvent<HudVitalsPayload>("kora_hud:vitals", (payload) => {
        if (payload) setVitals(payload)
    })

    useNuiEvent<HudUpdatePayload>("kora_hud:update", (payload) => {
        if (payload) setUpdate(payload)
    })

    // Unlike the other handlers, `payload` legitimately being `null` (on
    // foot) is a real state, not a "message dropped" signal -- so this
    // doesn't gate on truthiness the way kora_hud:config/kora_hud:update do.
    useNuiEvent<HudVehiclePayload>("kora_hud:vehicle", (payload) => {
        setVehicle(payload ?? null)
    })

    useNuiEvent<HudPlayerIdPayload>("kora_hud:playerId", (payload) => {
        setPlayerId(typeof payload === "number" && payload > 0 ? payload : null)
    })

    useNuiEvent<HudVisibilityPayload>("kora_hud:visibility", (payload) => {
        if (typeof payload === "boolean") setVisible(payload)
    })

    useNuiEvent<HudLayoutModePayload>("kora_hud:layoutMode", (payload) => {
        if (typeof payload !== "boolean") return
        if (payload) {
            initialOffsetsRef.current = offsetsRef.current
            initialScalesRef.current = scalesRef.current
            initialJustificationsRef.current = justificationsRef.current
            initialGaugesBottomAnchoredRef.current = gaugesBottomAnchoredRef.current
            initialMinimapVehicleOnlyRef.current = minimapVehicleOnlyRef.current
            initialHiddenRef.current = hiddenRef.current
            initialSettingsRef.current = settingsRef.current
        } else {
            setSelected(null)
            for (const timer of Object.values(pendingPreviewRef.current)) window.clearTimeout(timer)
            pendingPreviewRef.current = {}
        }
        setLayoutEditing(payload)
    })

    useNuiEvent<HudLayoutResetPayload>("kora_hud:layoutReset", () => {
        // Lua has already deleted the KVP key, so this deliberately does NOT
        // post anything back -- it only drops what the page is holding, which
        // leaving edit mode does not do. Ignores the payload value: the
        // message arriving at all is the event.
        applyOffsets({})
        applyScales({})
        applyJustifications({})
        setGaugesBottomAnchored(true)
        setMinimapVehicleOnly(minimapVehicleOnlyDefaultRef.current)
        applyHidden({})
        applySettings({})
    })

    // client/hud.lua's resource-start SendNUIMessage calls are best-effort --
    // FiveM drops them if this page hasn't mounted (and attached its
    // "message" listener) yet, which is common for a player already logged
    // in when kora_hud (re)starts. This ping is the guaranteed half of the fix:
    // once mounted, ask Lua for a fresh push instead of hoping the first one
    // landed. See client/hud.lua's "kora_hud:ready" callback for the other half.
    useEffect(() => {
        fetchNui("kora_hud:ready").catch((error) => {
            console.error("[kora_hud] kora_hud:ready ping failed:", error)
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
            scales,
            justifications,
            gaugesBottomAnchored,
            minimapVehicleOnly,
            minimapVehicleOnlyAllowed: config.layout?.minimapVehicleOnlyAllowed !== false,
            commitOffset,
            commitScale,
            commitJustification,
            setGaugesBottomAnchored,
            setMinimapVehicleOnly,
            resetToDefaults,
            editor: config.layout?.editor ?? DEFAULT_EDITOR,
            hidden,
            settings,
            elements,
            selected,
            select,
            setHidden,
            setSetting,
            resetElement,
            preview,
            confirm,
            cancel,
        }),
        [config.layout, layoutEditing, offsets, scales, justifications, gaugesBottomAnchored, minimapVehicleOnly, hidden, settings, elements, selected, commitOffset, commitScale, commitJustification, setGaugesBottomAnchored, setMinimapVehicleOnly, resetToDefaults, select, setHidden, setSetting, resetElement, preview, confirm, cancel],
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
                            <HudVehicleContext.Provider value={vehicle}>
                                <HudPlayerIdContext.Provider value={playerId}>{children}</HudPlayerIdContext.Provider>
                            </HudVehicleContext.Provider>
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

/** Local server ID shown only after the player runs `/id`. */
export function useHudPlayerId() {
    return useContext(HudPlayerIdContext)
}

/** Whether the HUD should render at all (login state and the show/hide exports). */
export function useHudVisible() {
    return useContext(HudVisibleContext)
}

/** Per-player section offsets and layout-editor state. */
export function useHudLayout() {
    return useContext(HudLayoutContext)
}
