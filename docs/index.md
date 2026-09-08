---
layout: default
title: qbhud
---

Configurable HUD for FiveM, built on qblib's cache primitives and qbtheme. All
player data (job, gang, cash, bank, hunger/thirst, stress, seatbelt) comes
through a single adapter interface (`HudBridge`, documented in
`shared/bridge.lua`) rather than framework calls scattered through the render
code — `client/hud.lua` only ever calls `HudBridge.getSnapshot()` /
`HudBridge.onChange()` / `HudBridge.isLoggedIn()`, so swapping the adapter
never touches HUD logic. The qbcore adapter also observes the server-owned
`LocalPlayer.state['qbmultichar:mode']` key: selection, mandatory spawning,
and the scene studio remain hidden even after `qbcore:loggedIn` becomes true,
until that cinematic mode clears. Two adapters ship today:
`client/bridge/qbcore.lua`
sources live data from qbcore's replicated player mirror (delta-pushed, not
polled), and `client/bridge/stub.lua` fabricates normalized mock data with no
framework installed at all, for standalone use or UI development. Which one
loads is a `fxmanifest.lua` `client_scripts` choice, documented by
`Config.bridge.adapter`.

## Requirements

- [qblib](https://qbcore2.github.io/qblib/)
- qbcore — **optional**. Only needed if you keep the shipped `qbcore` bridge
  adapter (`client/bridge/qbcore.lua`) loaded. Swap `fxmanifest.lua`'s
  `client_scripts` to `client/bridge/stub.lua` instead and qbhud runs
  standalone with mock player data, no framework required.

## Installation

`server.cfg`, in this order:
```
ensure qblib
ensure qbcore
ensure qbhud
```
(Drop `ensure qbcore` if you're running the stub adapter instead — see below.)

By default `fxmanifest.lua` lists `client/bridge/qbcore.lua` in
`client_scripts`, and `config.lua`'s `Config.bridge.adapter` is set to
`"qbcore"` to match. To run without qbcore, edit `fxmanifest.lua` to load
`client/bridge/stub.lua` in its place and set `Config.bridge.adapter =
"stub"` for consistency — `Config.bridge.adapter` itself is a documentation
field (every adapter file's header comment references it), the actual load
is driven by which file `client_scripts` lists. `client/hud.lua` needs no
changes either way.

## Usage examples

### Switch the bridge adapter (qbcore -> standalone stub)
```lua
-- fxmanifest.lua
client_scripts {
    'client/bridge/stub.lua',   -- was 'client/bridge/qbcore.lua'
    'client/voice.lua',
    'client/vehicle.lua',
    'client/hud.lua'
}
```
```lua
-- config.lua
Config.bridge = {
    adapter = "stub",   -- was "qbcore"
}
```
The stub seeds `cash = 500`, `bank = 5000`, full hunger/thirst, and slowly
drains hunger/thirst every minute so the HUD visibly updates with nothing
else installed.

### Toggle which HUD elements render
```lua
-- config.lua
Config.hud = {
    dynamic = true,   -- hide gauges (health/stamina/hunger/thirst/fuel/armour/stress)
                       -- while they're at their neutral value
    elements = {
        mic          = true,
        cash         = true,
        bank         = true,
        hungerThirst = true,
        stamina      = true,
        stress       = false,  -- e.g. disable the stress gauge entirely
        vehicle      = true,   -- speed/fuel/engine/headlights/seatbelt, in-vehicle only
    },
}
```
`elements.mic` also gates the voice-talking sampler thread in
`client/voice.lua` (`Voice.setActive`) — disabling it stops
`NetworkIsPlayerTalking` polling entirely, not just the on-screen icon.

### Show cash and bank one at a time
```lua
-- config.lua
Config.hud.money = {
    scrollAccounts     = true,   -- one account at a time instead of both rows
    scrollAccountsTime = 5000,   -- ms each account is shown for
}
```
Off by default — cash and bank side by side is the pre-existing behaviour, and
upgrading shouldn't silently hide half of it. Cycling only happens when
**both** `elements.cash` and `elements.bank` are on; with one of them off
there's nothing to alternate with, so the enabled account is simply shown
permanently. The swap is a short fade/slide on the money row only, nothing
else in the panel moves.

### Let players move HUD sections
```
/hudlayout        -- enter layout edit mode; Confirm or Cancel to leave
/hudlayoutreset   -- forget the saved layout, back to the shipped positions
/id               -- show or hide your local server ID in the player HUD
```
```lua
-- config.lua
Config.layout = {
    movable = true,             -- false pins the layout for everyone
    command = 'hudlayout',
    kvpKey  = 'qbhud:layout',
}
```
Four HUD sections can be repositioned and resized (75%–150%), each persisted under a stable id: `gauges`
(bottom-centre — the gauge row), `vehicle` (bottom-centre — vehicle telemetry), `identity`
(bottom-right — mic, job/gang, money) and `status` (top-right — active status
effects), plus `chatInput` (the qbchat composer), which can be repositioned and resized.
The chat preview in the
editor moves and scales only the input and its command suggestions; received messages
stay in their normal position.

`/hudlayout` is an explicit **mode**, not an always-on affordance: the HUD is a
click-through overlay during play and has to stay that way, so it takes NUI
focus, dims the screen and puts a move handle plus a resize grip on each resizable
section. Drag the resize grip left or right to adjust its size. These are regular
pointer gestures, not browser HTML5 drag-and-drop controls. **Confirm** saves the
new positions and component sizes; **Cancel** (or Escape) restores the layout from when
the editor opened; either action hands focus back to the game. Dragging itself
only previews the layout and does not write it.

There is no editor panel across the top of the HUD. Each resizable section has
its own attached Move, Resize and Align icons: drag Move to reposition (hold
Control to snap to a 5% viewport grid; hold Shift to snap to 45° angles), drag Resize left or right to scale, and click Align to cycle Left, Centre and Right
for the elements inside it; the component itself stays where it was placed.
The gauge row also has an Anchor toggle. It is on by default, keeping gauges
near the bottom of the screen while on foot, then moving them above the vehicle
panel as it slides in. Turn it off to keep gauges at their fixed layout position.
A compact three-icon container in the centre of the screen confirms the preview,
closes without saving, or resets to the shipped layout.

Offsets are stored as **fractions of the viewport**, not pixels. The editor
keeps each section's rendered box on screen, so a status stack can be placed
flush with the bottom edge without its controls becoming unreachable. This also
works correctly on scaled high-resolution displays. Each section's shipped
corner remains its zero point, so a player with nothing saved sees exactly the
default layout.

Storage is a client-side FiveM KVP key (`Config.layout.kvpKey`), so a layout is
per player *and per machine*: no database column, no server round trip, and
nothing about it ever leaves the client. The stored blob is treated as
untrusted input on read and re-validated/clamped on write in `client/hud.lua`
— the NUI stays render-only and has no authority over anything but where it
draws its own boxes. `movable = false` makes `/hudlayout` report that moving
sections is disabled instead of opening the editor.

### Drive HUD values manually for testing (stub adapter only)
```
/hudtest_cash 1500
/hudtest_bank 25000
/hudtest_stress 40
```
These commands are registered by `client/bridge/stub.lua` only — they don't
exist when the qbcore adapter is loaded, since job/cash/etc. there come from
qbcore itself (`exports.qbcore:addMoney`, `exports.qbcore:setJob`, ...).

### Toggle the seatbelt placeholder
```
/hud_toggleseatbelt
```
Bound to `B` by default via `QB.keybind`. Stock FiveM has no seatbelt
native at all, so both adapters own this as local placeholder state until a
real seatbelt system is wired into a vehicle resource.

### Point the mic indicator at a different voice resource
```lua
-- config.lua
Config.voice = {
    enabled  = true,
    resource = "qbvoice",
}
```
`client/voice.lua` reads FiveM's own `NetworkIsPlayerTalking` native, which
reflects whichever Mumble-backed voice resource is running (pma-voice,
saltychat, mumble-voip all work without extra integration). The configured
resource may additionally expose `getTalkingMode() -> { index, name, label,
range }`; when it does, the mic pill shows the current mode, signal level and
range in metres. `qbvoice` provides that export. If it is absent or temporarily
unavailable, the HUD safely falls back to the original mic-only indicator.
`enabled = false` is a master kill switch for the whole indicator and its
shared-scheduler sampling task.

## API reference

qbhud exposes three client exports for other resources that need to take the
HUD off screen (cutscenes, cameras, custom pause menus):

```lua
exports.qbhud:hide()      -- force-hide the HUD regardless of login state
exports.qbhud:show()      -- clear the forced hide; login state still gates
exports.qbhud:isVisible() -- boolean: what the NUI is currently showing
```

`hide()` is an override, not a toggle of the login gate: logging in while
force-hidden keeps the HUD hidden until `show()` clears the override, and
`show()` during character select is a safe no-op (the HUD only ever renders
while a character is logged in). It exposes **no client/server net events**.
The other externally-triggerable actions are the `RegisterCommand`s listed in
Usage examples above (`hud_toggleseatbelt` always; `hudtest_cash`/
`hudtest_bank`/`hudtest_stress` on the stub adapter only), plus one internal
NUI callback (`qbhud:ready`, used by the web page's own mount handshake).

### Bridge adapter interface (`shared/bridge.lua`)

Every `client/bridge/<name>.lua` assigns a global `HudBridge` table satisfying
this contract; `client/hud.lua` never reaches past it into framework
internals:

```lua
---@class QBHudBridge
---@field getSnapshot fun(): QBHudBridgeSnapshot                        -- required
---@field getSeatbelt (fun(): boolean) | nil                            -- optional, cheap accessor
---@field onChange (fun(handler: fun(snapshot: QBHudBridgeSnapshot)): nil) | nil  -- optional, else polled
---@field isLoggedIn (fun(): boolean) | nil                             -- optional, else always visible
---@field onLoginChange (fun(handler: fun(loggedIn: boolean)): nil) | nil -- optional

---@class QBHudBridgeSnapshot
---@field job { name, label, grade, gradeLabel, onDuty }
---@field gang { name, label, grade, gradeLabel } | nil
---@field cash number
---@field bank number
---@field hunger number     -- 0-100
---@field thirst number     -- 0-100
---@field stress number     -- 0-100
---@field seatbelt boolean
---@field status { name, severity }[] | nil   -- qblib QB.status.getActive(), adapter-independent
```
Writing a new adapter (ESX, ox_core, ...) means implementing this table in a
new `client/bridge/<name>.lua`, listing it in `fxmanifest.lua`'s
`client_scripts` in place of the current adapter, and updating
`Config.bridge.adapter` to match — `client/hud.lua`, `client/vehicle.lua`, and
`client/voice.lua` need no changes.

## Config highlights (`config.lua`)

- `Config.hud.dynamic` — hide gauge elements while at their neutral value
  (full health/stamina/hunger/thirst/fuel, empty armour/stress).
- `Config.hud.elements.*` — per-element on/off (`mic`, `cash`, `bank`,
  `hungerThirst`, `stamina`, `stress`, `vehicle`). Health/armour/job/gang are
  always shown — they aren't independently toggleable.
- `Config.hud.money.scrollAccounts` / `.scrollAccountsTime` — show one money
  account at a time, alternating on that interval, instead of both rows. Only
  applies while both the `cash` and `bank` elements are enabled.
- `Config.hud.minimap` — `'always'` (never touch `DisplayRadar`), `'vehicle'`,
  or `'never'`.
- `Config.layout.movable` / `.command` / `.kvpKey` — per-player draggable HUD
  sections, saved client-side in KVP. See "Let players move HUD sections".
- `Config.bridge.adapter` — documents which adapter is loaded (`"qbcore"` by
  default); the actual load is driven by `fxmanifest.lua`'s `client_scripts`.
- `Config.voice.enabled` / `Config.voice.resource` — master mic toggle and
  the voice resource used for optional `getTalkingMode()` range details.
- `Config.voice.interval` (200ms) — mic sampling cadence. The sample task is
  skipped entirely unless the HUD is visible and the `mic` element is on.
- `Config.poll.*` — see "Update cadences" below.

## Update cadences

The HUD is written against a per-frame budget. Three rules hold everywhere in
`client/hud.lua`:

1. **Nothing runs per frame, and everything periodic shares one thread.** FiveM
   walks every live coroutine each frame to decide what to resume, so a
   sleeping thread costs something every frame whether or not it had work.
   Vitals flushes, player-data flushes, vehicle telemetry, the mic sample and
   the minimap re-assert are all *tasks* on one scheduler; each declares
   whether it has any reason to run, and the sleep is computed from the tasks
   themselves rather than being a fixed tick. `client/voice.lua` deliberately
   owns no thread of its own.
2. **Nothing polls a value something else can announce.** Health, armour,
   stamina, ped and vehicle lifecycle arrive as qblib cache notifications;
   job/money/needs arrive on the adapter's push path. Only vehicle telemetry
   and mic state are genuinely sampled, because nothing in the stack can
   announce them.
3. **No hot path reads back across the export boundary.** Every
   `QB.<module>.<fn>` access is a cross-resource export call, not a table
   lookup — announced values are mirrored into plain locals and kept current
   from the change handlers' own arguments.

Everything is gated on visibility: while the HUD is hidden — character select,
a cutscene, a logout — the resource owns **no thread** and does no work at all.

Element toggles decide what the HUD *subscribes to*, not just what it paints.
`elements.stamina = false` means the highest-frequency notification in the
resource is never subscribed to; `elements.vehicle = false` means no vehicle
native is ever sampled.

Each wire channel is rate-limited by a **leading-edge** throttle: the first
change goes out on the frame it happened, and only a further change inside the
interval is deferred to the scheduler's trailing pass.

- `Config.poll.vitalsInterval` (150ms) — health/armour/stamina/talking
  (`qbhud:vitals`). Stamina is the only field that moves continuously, so this
  is the cadence that decides the resource's cost while the player is moving.
  Values are rounded to whole units first, so float drift below what the gauges
  can render never reaches the wire. The value is forwarded to the NUI, which
  sets its gauge animation to match so the rings interpolate between samples
  rather than stepping — which makes this a pure cost knob: raise it to cut the
  message rate and the HUD looks exactly the same.
- `Config.poll.playerInterval` (100ms) — job/gang/money/needs/status
  (`qbhud:update`). Event-driven, so this only ever collapses a burst — e.g. a
  qbcore resync firing the adapter's four root subscriptions in one frame.
- `Config.poll.vehicleInterval` (250ms) — speed/fuel/engine/headlight refresh
  while in a vehicle (`qbhud:vehicle`). The sampling task is inactive while on
  foot, both edges (getting in, getting out) push immediately, and an unchanged
  reading — idling at a light — is sampled but not sent.
- `Config.poll.bridgeInterval` (500ms) — fallback poll cadence for adapters
  with no `onChange` push path (the qbcore adapter pushes instead and never
  uses this).
- `Config.poll.minimapInterval` (250ms) — how often `SETUP_HEALTH_ARMOUR` is
  re-issued to suppress the minimap's own health/armour cluster, which would
  otherwise disagree with the radial gauges. The usual snippet for this runs on
  a `Wait(0)` loop; the flag persists in the scaleform between calls, so a few
  times a second is enough. Set to `0` to restore per-frame behaviour if the
  stock cluster visibly flickers back in on your build.

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [qblib](https://qbcore2.github.io/qblib/) — shared helper library
- [qbsql](https://qbcore2.github.io/qbsql/) — database driver
- [qbcore](https://qbcore2.github.io/qbcore/) — framework core
- [qbinventory](https://qbcore2.github.io/qbinventory/) — headless inventory
- [qbtarget](https://qbcore2.github.io/qbtarget/) — targeting/interaction
- [qbclothing](https://qbcore2.github.io/qbclothing/) — clothing/wardrobe
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
