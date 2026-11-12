---
title: "How to use"
sidebar_position: 3
---


# How to use

kora_hud is an orchestrator (client/hud.lua) that merges kora_lib's cache (health/armour/stamina), the voice/vehicle samplers, and whichever HudBridge adapter is loaded into three NUI channels, plus a handful of one-shot/occasional messages. Everything below is the full Lua ⇄ NUI contract (web/src/lib/types.ts) and the integration points other resources actually use — the React page itself (web/src) is not reproduced here.

## The three data channels, by cadence not topic

Splitting by how often a value changes — not by what it means — is deliberate: stamina alone moves on every 100ms kora_lib cache tick for the whole length of a sprint, while the job label changes a handful of times an hour. Putting them on one message would serialize (and re-render) everything at the fastest member's rate.

```text title="wire payloads"
// action: "kora_hud:config" — sent once, on resource (re)start / NUI remount.
{
  dynamic: false,
  elements: { mic: true, cash: true, bank: true, hungerThirst: true, stamina: true, stress: true, vehicle: true },
  speedUnit: "kmh",        // "kmh" | "mph"
  vitalsInterval: 150,     // ms — gauge CSS animation is timed to match this
  money: { scrollAccounts: true, scrollAccountsTime: 5000 },
  layout: {
    movable: true, command: "hudlayout",
    minimapVehicleOnly: false, minimapVehicleOnlyDefault: false, minimapVehicleOnlyAllowed: true,
    offsets: { /* { [sectionId]: { x, y } } from this player's KVP */ },
    scales: { /* { [sectionId]: number } */ },
    justifications: { /* { [sectionId]: "left"|"center"|"right" } */ },
    gaugesBottomAnchored: true,
    hidden: { /* { [sectionId]: true } */ },
    settings: { /* { [sectionId]: { [settingKey]: value } } */ },
    editor: { enabled: true, allowHide: true, command: "ui", previewInterval: 100 },
  },
}

// action: "kora_hud:vitals" — throttled to Config.poll.vitalsInterval (leading-edge:
// an isolated change is sent at once, only a BURST inside the interval is coalesced).
{ health: 184, maxHealth: 200, armour: 0, stamina: 76, talking: false, voiceMode: { index: 2, name: "normal", label: "Normal", range: 10 } }

// action: "kora_hud:update" — pushed when the bridge adapter reports a delta
// (kora_core: money/job/gang/metadata roots), or every Config.poll.playerInterval
// as a ceiling. Never carries vitals or vehicle telemetry.
{
  job: { name: "police", label: "Police", grade: 2, gradeLabel: "Officer", onDuty: true },
  gang: null,
  cash: 500, bank: 12400,
  hunger: 87, thirst: 92, stress: 10,
  status: [ { name: "bleeding", severity: 1 } ],
}

// action: "kora_hud:vehicle" — Config.poll.vehicleInterval ceiling, only sent when a
// field actually changed; null the instant the player is no longer in a vehicle.
{ speed: 62, speedUnit: "kmh", fuel: 74, fuelKind: "fuel", engineOn: true,
  headlights: "low", seatbelt: true, harness: false, progress: false }
```

- `kora_hud:vitals` — health, armour, stamina, mic talking state and voice proximity mode. Ceiling `Config.poll.vitalsInterval` (default 150ms). Values are rounded to whole units in Lua before sending, so a message always means a visible change.
- `kora_hud:update` — job, gang, cash, bank, hunger, thirst, stress, active kora_lib status effects (bleeding/limping/etc). Ceiling `Config.poll.playerInterval` (default 100ms), but in practice event-driven off the bridge adapter's own push path.
- `kora_hud:vehicle` — speed, fuel, fuelKind, engineOn, headlights, seatbelt, harness, progress-bar-active. Ceiling `Config.poll.vehicleInterval` (default 250ms), sampled only while `Kora.cache.vehicle()` says the player is in a vehicle, and only sent when something in the payload actually differs from the last one sent (an idling car sends nothing).

## Other one-shot / occasional messages

- `kora_hud:visibility` (boolean) — sent once at start and again on every login/logout transition. Composes `HudBridge.isLoggedIn()` (always `true` if the adapter has no login concept), the force-hide flag (`exports.kora_hud:hide()`/`:show()`), and resource-stop.
- `kora_hud:playerId` (number | nothing) — the local `/id` command toggles this on/off for yourself.
- `kora_hud:compat` (`HudCompat.state`) — `{ dynamicHealth, altitude, showSeatbelt, cruise, harness, nitrous: { level, active } }`, driven by the legacy `hud:client:*` events (see Compat below).
- `kora_hud:layoutMode` (boolean) and `kora_hud:layoutReset` (boolean) — entering/leaving the layout editor (`/hudlayout` or `/ui`) and `/hudlayoutreset`/`/uireset` respectively.
- `kora_hud:uiElements` (array of element defs) — every element another resource registered through `exports.kora_hud:registerUiElement`, plus the minimap, whenever the registry changes (coalesced over 100ms) or the editor opens.

## NUI → Lua callbacks (the only two with real logic)

- `kora_hud:ready` — the React page pings this once mounted. Lua answers `cb({})` unconditionally first, then re-sends the full initial state (config/visibility/compat/layout/uiElements). This exists because `SendNUIMessage` behaves like `postMessage`: a message sent before the page's listener is attached is lost, not queued, which would otherwise strand every `ensure kora_hud` done while a player is already logged in.
- `kora_hud:uiPreview` — live drag preview while the `/ui` editor is open, `{ elements: { [id]: { x, y, scale, hidden, settings } }, final? }`. Re-validated against each element's own schema (`HudUi.layoutFor`) before being relayed to its owner as the local event `kora_hud:ui:apply(owner, id, layout, "preview")`. The minimap only applies on `final === true` (the drop), never on every drag frame.
- `kora_hud:finishLayout` — `{ confirmed, offsets, scales, justifications, hidden, settings, gaugesBottomAnchored, minimapVehicleOnly }` from Confirm/Cancel. Only `confirmed === true` persists anything (re-validated, same as every value kora_hud reads back from its own KVP). Either way this closes the editor and notifies every registered owner.

## Config.hud — what players always see vs. what is toggleable

- Health, armour and job/gang are **not** in `Config.hud.elements` — they are treated as baseline "usual player data", always rendered (though `Config.hud.dynamic` can still hide a neutral health/armour ring). The only per-element toggles are `elements.mic`, `.cash`, `.bank`, `.hungerThirst`, `.stamina`, `.stress`, `.vehicle` (speed/fuel/engine/headlights/seatbelt together, shown only in a vehicle). Turning an element off also stops kora_hud **subscribing to or sampling** it — e.g. `elements.stamina = false` means the highest-frequency kora_lib notification in the whole HUD is never even registered, and `elements.vehicle = false` means vehicle natives are never polled.
- `Config.hud.dynamic` (default `false`) — when `true`, radial gauges only render while they differ from their neutral value: full health/stamina/hunger/thirst/fuel and empty armour/stress are hidden. Non-gauge elements are unaffected. Defaults off so upgrading a server never silently hides gauges players are used to seeing.
- `Config.hud.avoidProgressBar` (default `true`, live) / `Config.hud.avoidHarnessBar` (default `false`, live) — while a kora_lib progress bar (or the race-harness attach/remove bar) is showing in a vehicle, the gauge row lifts above it so neither one is covered.
- `Config.hud.money` — `{ scrollAccounts = true, scrollAccountsTime = 5000 }`. Only alternates cash/bank display when **both** `elements.cash` and `elements.bank` are enabled; with only one enabled it is simply shown permanently.
- `Config.hud.minimap` — `'always'` (kora_hud never touches `DisplayRadar`, so another resource's own radar hide, e.g. for a cutscene, still works), `'vehicle'` (shown only while in a vehicle), or `'never'` (always hidden).
- `Config.hud.minimapToggle` — the player-facing `/minimap` (default command name) toggle layered on top of the mode above: `enabled` (live), `command`, `defaultKey` (unbound `''` by default, rebindable in Settings), `remember` (persists the choice in a client KVP, live), `defaultVisible` (what a player with no saved choice sees, live), `allowOnFoot` (live — lets a player lift the `'vehicle'` gate for themselves on foot; `minimap = 'never'` is never overridden by anything).
- `Config.hud.minimapVehicleOnly` — a **separate**, per-player `/hudlayout`-saved switch ("Minimap only in vehicle"): `default` (server default for players who never changed it, live) and `allowPlayerChange` (hides the switch and forces `default` for everyone when `false`, live; also forced while `Config.layout.movable` is `false`).
- `Config.hud.hideMinimapWhenForcedHidden` (default `true`, live) — while another resource force-hides the whole HUD (`exports.kora_hud:hide()`, as kora_clothing does for its menu), also keep the radar hidden, and let `minimap` take back over on `:show()`. `false` restores the old behaviour of handing the radar back as visible (which shows it on foot under `minimap = 'vehicle'`).
- `Config.hud.hideOnPauseMenu` (default `true`, live) — hides every element (gauges, job/cash, status effects, vehicle bar) while the pause menu or full map (Esc/P) is open.
- `Config.hud.minimapLayout` — positions the minimap/mask/border together and, for `shape = 'square'` (default), swaps the stock round mask for a streamed square texture (`stream/kora_hud_squaremap.ytd`, built by `tools/gen_minimap_ytd.py`). `shape = 'circle'` keeps the stock round mask with the same clip type; `shape = 'stock'` (or `enabled = false`) touches nothing and undoes any earlier change. Sub-keys: `textureDict`/`maskTexture` (the streamed names), `dictTimeoutMs`/`retryMs`/`maxRetries` (streaming grace + retries), `bigmapWaitMs`/`readySettleMs`/`readyTimeoutMs`/`pollMs` (the bigmap-toggle refresh this all rides on), `guardBigmap` (forces an unexpectedly-stuck bigmap back off, live), `aspectOffset` (ultrawide x correction), `shapes` (the raw per-shape rects), and the live-tunable `x`/`y`/`scale`/`safezoneCompensation`/`offsets` nudges on top of them.
- `Config.hud.speedUnit` — `'kmh'` or `'mph'` for the vehicle speedometer (live; converts and relabels atomically so a value and its unit can never desync across a dropped message).

## Other Config tables

- `Config.layout` — `{ movable = true, command = 'hudlayout', kvpKey = 'kora_hud:layout' }`. `movable = false` pins every section for everyone; the command then reports moving is disabled instead of opening the editor. Everything is stored client-side in a FiveM KVP as JSON — nothing here ever reaches the server.
- `Config.uiEditor` — the unified `/ui` editor layered over `/hudlayout`: `enabled` (keeps the classic editor when `false`), `command = 'ui'` / `aliases = { 'hudsettings' }`, `resetCommand = 'uireset'`, `allowHide` (live — lets players hide individual elements), `allowExternal` (`false` = HUD sections only, no other resource's elements), `minimap` (live — lets players drag/resize the minimap in `/ui`, needs `minimapLayout.enabled` and a non-`'stock'` shape), `previewInterval` (ms between live-drag previews sent to element owners).
- `Config.seatbelt` — `harnessIcon` (`'attached'` | `'always'` | `'off'`, live) controls the race-harness icon beside the seatbelt icon. `sound` controls the buckle/unbuckle sound: `enabled` (live), `volume` 0.0–1.0 (NUI backend only), `backend` (`'nui'` plays the bundled `.wav`s through the HUD's own frame at the configured volume; `'native'` uses fixed-volume GTA frontend sounds), `buckleFile`/`unbuckleFile` (must also be listed in `fxmanifest.lua`'s `files` if changed), `native.buckle`/`native.unbuckle` (`{ name, set }` for `PlaySoundFrontend`).
- `Config.bridge.adapter` — currently `"kora_core"`. Selects `client/bridge/kora_core.lua` as the adapter per the comment in `fxmanifest.lua`; swapping frameworks means writing a new `client/bridge/<name>.lua` against the contract in shared/bridge.lua (see the Bridge adapter contract module below), changing this value, and changing the client_scripts entry — `client/hud.lua` itself never changes.
- `Config.voice` — `{ enabled = true, resource = "kora_voice", interval = 200 }`. `enabled` is the master mic-indicator toggle; `resource` names the export kora_hud calls for the proximity label (see the Voice integration module); `interval` (ms) is how often the HUD samples `NetworkIsPlayerTalking` — the one piece of mic state with no change notification of its own, sampled only while the HUD is visible and `elements.mic` is on.
- `Config.poll` — every value is a **ceiling**, not a fixed-rate timer: a leading-edge throttle sends an isolated change immediately and only coalesces a burst inside the interval. `vitalsInterval` (150), `playerInterval` (100), `vehicleInterval` (250), `bridgeInterval` (500 — how often `HudBridge.getSnapshot()` is polled as a fallback when the adapter has no `onChange` push path), `minimapInterval` (250 — how often `SETUP_HEALTH_ARMOUR` is re-issued to suppress the engine's own health/armour cluster on the minimap scaleform; `0` restores a per-frame assert if the stock cluster ever visibly flickers back in).
- `Config.stress` — see the Stress gain module below; this is the one place kora_hud actively changes authoritative state rather than only displaying it.

## Integration examples: updating state another resource owns

kora_hud deliberately owns none of hunger/thirst/stress/job/gang/money — that is kora_core's job, pushed through the bridge adapter. A third-party resource integrates at one of three points:

```text title="another resource integrating with kora_hud"
-- Permanently raise stress by 10 (kora_core owns the value; kora_hud just displays it)
TriggerServerEvent('QBCore:Server:SetMetaData', 'stress', math.min(100, (currentStress or 0) + 10))

-- Implement the voice contract so Config.voice.resource = 'my_voice' shows a range label
exports('getTalkingMode', function()
    return { index = 2, name = 'whisper', label = 'Whisper', range = 2.0 }
end)

-- Tell kora_hud the seatbelt state changed (fired locally, same event the stub bridge raises)
TriggerEvent('seatbelt:client:ToggleSeatbelt', true)
```

- Permanent hunger/thirst/stress/money/job changes: call **kora_core**'s own metadata/money/job exports (or `TriggerServerEvent('QBCore:Server:SetMetaData', 'stress', value)`, the same compat event client/stress.lua itself uses). kora_hud will reflect it the instant `exports.kora_core:onPlayerDataChange` fires for that root — there is nothing to call on kora_hud itself.
- Voice proximity label: implement `exports.<yourResource>:getTalkingMode()` returning `{ index, name, label, range }` and point `Config.voice.resource` at it. kora_hud polls it every `Config.voice.interval` ms while the mic is sampled; a malformed or erroring return is treated as "no mode" (range hidden, mic icon unaffected).
- Seatbelt / harness: fire the local client events `seatbelt:client:ToggleSeatbelt(enabled)` and `seatbelt:client:ToggleHarness(attached)` from whatever resource owns the mechanic (kora_utils today). kora_hud updates the vehicle-panel icon and (seatbelt only) plays the buckle/unbuckle sound from these events; it never originates the state itself. `seatbelt:client:UseHarness` (no payload) additionally tells kora_hud a harness-attach *bar* just started, so the gauge row can lift the same way it does for a kora_lib progress bar.
