// The full Lua -> NUI message contract for qb-hud. Every message from Lua
// arrives as a `window` `message` event shaped like NuiWireMessage below (see
// useNuiEvent.ts). qb-hud only ever sends fire-and-forget messages (no
// request/response round trip -- there's nothing for the player to answer)
// from client/hud.lua. Keep this file in sync with that file's QB.nui.send
// call sites.

export interface NuiWireMessage<T = unknown> {
    action: string
    data: T
}

// action: "qbhud:config" -- sent once on resource start.
export interface HudConfigPayload {
    elements: {
        mic: boolean
        cash: boolean
        bank: boolean
        hungerThirst: boolean
        stamina: boolean
        stress: boolean
        vehicle: boolean
    }
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
    seatbelt: boolean
}

// action: "qbhud:update" -- sent on every cache/bridge refresh (see
// client/hud.lua's pushUpdate). `vehicle` is undefined/null while on foot.
export interface HudUpdatePayload {
    health: number
    armour: number
    stamina: number
    talking: boolean
    job: HudJob
    gang: HudGang | null
    cash: number
    bank: number
    hunger: number
    thirst: number
    stress: number
    vehicle: HudVehicleInfo | null
}
