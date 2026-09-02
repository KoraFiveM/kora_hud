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
    /**
     * Config.poll.vitalsInterval, in ms -- how often Lua can send a
     * "qbhud:vitals" message at most. The gauges animate over exactly this
     * long so each ring interpolates from one sample to the next instead of
     * stepping, which is what lets a server raise the interval to cut message
     * rate without the HUD looking any less smooth.
     */
    vitalsInterval: number
}

// action: "qbhud:theme" -- QB.theme.tokens() from qblib, forwarded verbatim.
// Keys are CSS custom-property names (no leading "--"); values are ready-to-
// apply HSL-triplet strings. See qblib's modules/theme/docs.md.
export type HudThemePayload = Record<string, string>

// action: "qbhud:visibility" -- sent once on resource start (reflecting
// whatever the bridge adapter's initial login state is) and again on every
// login/logout transition. Absent an adapter with a login concept, this is
// always true. See shared/bridge.lua's HudBridge.isLoggedIn/onLoginChange.
export type HudVisibilityPayload = boolean

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
    speed: number
    fuel: number | null
    engineOn: boolean
    headlights: "off" | "low" | "high"
    seatbelt: boolean
}

// One entry per active qblib QB.status effect (e.g. "bleeding", "limping",
// "high_weed") -- see qblib's modules/status. `severity` is whatever the
// effect definition's severityLevels scale means for that specific effect;
// the HUD doesn't interpret it beyond passing it to a per-name icon/style
// lookup the effect's own consumer resource owns.
export interface HudStatusEffect {
    name: string
    severity: number | null
}

// action: "qbhud:vitals" -- the continuously-moving player stats, rate-limited
// to Config.poll.vitalsInterval (see client/hud.lua's `throttle`). This is the
// HUD's fastest non-vehicle channel: stamina alone changes on every qblib
// cache tick while sprinting. Every number here is already rounded to a whole
// unit in Lua, so a value arriving at all means it moved by at least one unit.
export interface HudVitalsPayload {
    health: number
    maxHealth: number
    armour: number
    stamina: number
    talking: boolean
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
