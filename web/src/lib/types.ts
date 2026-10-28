// The full Lua -> NUI message contract for qb-hud. Every message from Lua
// arrives as a `window` `message` event shaped like NuiWireMessage below (see
// useNuiEvent.ts). qb-hud only ever sends fire-and-forget messages (no
// request/response round trip -- there's nothing for the player to answer)
// from client/hud.lua. Keep this file in sync with that file's SendNUIMessage
// call sites.
//
// The three data channels ("qbhud:vitals", "qbhud:update", "qbhud:vehicle")
// are split by how FAST each one changes, not by topic. Stamina moves on
// every 100ms cache tick for the whole length of a sprint; the job label and
// the status list change a handful of times an hour. Keeping them on one
// message would mean serializing (and re-rendering) all of it at the fastest
// member's rate -- hudState.tsx gives each channel its own context for the
// same reason.

export interface NuiWireMessage<T = unknown> {
    action: string
    data: T
}

// action: "qbhud:config" -- sent once on resource start.
export interface HudConfigPayload {
    dynamic: boolean
    elements: {
        mic: boolean
        cash: boolean
        bank: boolean
        hungerThirst: boolean
        stamina: boolean
        stress: boolean
        vehicle: boolean
    }
    /** Unit used by the vehicle speedometer. Missing payloads default to km/h. */
    speedUnit?: HudSpeedUnit
    /**
     * Config.poll.vitalsInterval, in ms -- how often Lua can send a
     * "qbhud:vitals" message at most. The gauges animate over exactly this
     * long so each ring interpolates from one sample to the next instead of
     * stepping, which is what lets a server raise the interval to cut message
     * rate without the HUD looking any less smooth.
     */
    vitalsInterval: number
    /**
     * Config.hud.money. Optional, like `layout` below: a "qbhud:config"
     * message REPLACES the whole config object (see hudState.tsx), so a
     * payload from an older client/hud.lua that never sent this key would
     * leave it genuinely absent at runtime whatever the type claimed. Typed
     * optional so consumers are forced to handle that instead of reading
     * through undefined.
     */
    money?: HudMoneyConfig
    /** Config.layout plus this player's own saved section offsets. */
    layout?: HudLayoutConfig
}

export type HudSpeedUnit = "kmh" | "mph"

export interface HudMoneyConfig {
    /**
     * Show one account at a time, alternating, instead of cash and bank side
     * by side. Only has anything to alternate BETWEEN while both
     * `elements.cash` and `elements.bank` are on -- with one of them off the
     * enabled account is simply shown permanently.
     */
    scrollAccounts: boolean
    /** ms each account is shown for before switching. */
    scrollAccountsTime: number
}

/**
 * One section's position, as a FRACTION of the viewport rather than pixels: a
 * layout saved on a 3440x1440 ultrawide would put half the HUD off screen on
 * a 1920x1080 monitor otherwise. client/hud.lua validates each section against
 * its anchor-aware bounds on read and write, while the editor also keeps the
 * rendered section inside the viewport during a drag.
 */
export interface HudLayoutOffset {
    x: number
    y: number
}

export type HudLayoutJustification = "left" | "center" | "right"

export interface HudLayoutConfig {
    /** False pins the layout for everyone -- sections are never draggable. */
    movable: boolean
    /** Command that opens the layout editor, shown in the editor's own hint. */
    command: string
    /**
     * `{ [sectionId]: offset }` read back from this player's KVP, keyed by the
     * ids in components/hud/LayoutEditor.tsx. Sent with the config rather than
     * on a channel of its own so the HUD's first paint is already in the right
     * place instead of visibly jumping.
     */
    offsets: Record<string, HudLayoutOffset>
    /** Per-section scale, constrained by Lua to 75% through 150%. */
    scales: Record<string, number>
    /** Per-section alignment for the elements inside that section. */
    justifications: Record<string, HudLayoutJustification>
    /** True keeps gauges at the screen bottom until vehicle telemetry appears. */
    gaugesBottomAnchored: boolean
}

// action: "qbhud:layoutMode" -- the player entered layout edit mode with
// Config.layout.command or left through Confirm/Cancel. Lua owns NUI focus (see the
// SetNuiFocus call beside the send), so the NUI only reacts visually and
// starts accepting drags; it never asks for focus itself.
export type HudLayoutModePayload = boolean

// action: "qbhud:layoutReset" -- /hudlayoutreset deleted the stored layout.
// Separate from "qbhud:layoutMode" because a reset also has to discard
// offsets the NUI is holding in memory, which leaving edit mode does not.
export type HudLayoutResetPayload = boolean

// action: "qbhud:visibility" -- sent once on resource start (reflecting
// whatever the bridge adapter's initial login state is) and again on every
// login/logout transition. Absent an adapter with a login concept, this is
// always true. See shared/bridge.lua's HudBridge.isLoggedIn/onLoginChange.
export type HudVisibilityPayload = boolean

// action: "qbhud:playerId" -- emitted by the local `/id` command. A missing
// data value means the badge should be hidden.
export type HudPlayerIdPayload = number | null

export interface HudJob {
    name: string
    label: string
    grade: number
    gradeLabel: string
    onDuty: boolean
}

export interface HudGang {
    name: string
    label: string
    grade: number
    gradeLabel: string
}

export interface HudVehicleInfo {
    /** Whole-number speed in the unit carried atomically beside it. */
    speed: number
    /** Repeated here so a speed value can never render with a stale label. */
    speedUnit: HudSpeedUnit
    fuel: number | null
    /** `charge` for a vehicle qbfuel classifies as electric; otherwise fuel. */
    fuelKind: "fuel" | "charge"
    engineOn: boolean
    headlights: "off" | "low" | "high"
    seatbelt: boolean
}

// One entry per active kora_lib QB.status effect (e.g. "bleeding", "limping",
// "high_weed") -- see kora_lib's modules/status. `severity` is whatever the
// effect definition's severityLevels scale means for that specific effect;
// the HUD doesn't interpret it beyond passing it to a per-name icon/style
// lookup the effect's own consumer resource owns.
export interface HudStatusEffect {
    name: string
    severity: number | null
}

// action: "qbhud:vitals" -- the continuously-moving player stats, rate-limited
// to Config.poll.vitalsInterval (see client/hud.lua's `throttle`). This is the
// HUD's fastest non-vehicle channel: stamina alone changes on every kora_lib
// cache tick while sprinting. Every number here is already rounded to a whole
// unit in Lua, so a value arriving at all means it moved by at least one unit.
export interface HudVitalsPayload {
    health: number
    maxHealth: number
    armour: number
    stamina: number
    talking: boolean
    /** Current proximity voice mode. Missing/null when the voice resource does not expose it. */
    voiceMode?: HudVoiceMode | null
}

export interface HudVoiceMode {
    index: number
    name: string
    label: string
    range: number
}

// action: "qbhud:update" -- the slow, framework-sourced half of the player
// state, pushed when the bridge adapter reports a delta (or on
// Config.poll.bridgeInterval for an adapter with no push path). Vitals and
// vehicle telemetry are deliberately NOT included -- see HudVitalsPayload
// above and HudVehiclePayload below -- so this payload never has to go out at
// their much faster cadence.
export interface HudUpdatePayload {
    job: HudJob
    gang: HudGang | null
    cash: number
    bank: number
    hunger: number
    thirst: number
    stress: number
    status: HudStatusEffect[]
}

// action: "qbhud:vehicle" -- sent independently of "qbhud:update" (see
// client/hud.lua's pushVehicleUpdate), on the faster Config.poll.vehicleInterval
// cadence while driving, and only when a value actually changed (a car idling
// at a light sends nothing). `null` while on foot.
export type HudVehiclePayload = HudVehicleInfo | null
