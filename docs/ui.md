---
title: UI
sidebar_position: 8
---

# UI

The HUD is a click-through NUI page (`web/build/index.html`) owned by this resource. It only takes focus while the layout editor is open.

## Sections

The HUD page has four movable sections, each with a stable id used by the layout editor:

| Id | Default position | Contents |
| --- | --- | --- |
| `gauges` | bottom centre | Health, armour, stamina, hunger, thirst, stress gauges. |
| `vehicle` | bottom centre | Vehicle telemetry: speed, fuel or charge, engine, headlights, seatbelt, race harness. Only while in a vehicle. |
| `identity` | bottom right | Mic indicator, job/gang, cash and bank. |
| `status` | top right | Active status effects (names and severity from `Kora.status`). |

A fifth id, `chatInput`, is the `kora_chat` composer; it is stored in the same layout and applied by `kora_chat`. Elements registered by other resources and the minimap appear in the `/ui` editor as well. See [UI editor](./ui-editor.md).

## Visibility rules

The HUD shows only while all of these hold:

- the bridge reports a logged-in character (with the `kora_core` adapter: `kora_core:loggedIn` is true, `kora_multichar:mode` is falsy and the player data mirror is available);
- no other resource has called `exports.kora_hud:hide()`;
- the pause menu or full map is not open, when `Config.hud.hideOnPauseMenu` is on.

While hidden the resource owns no running thread and does no sampling.

## Gauges and money

- With `Config.hud.dynamic` gauges are hidden while at their neutral value.
- Cash and bank can alternate one at a time (`Config.hud.money`).
- `/id` shows your server ID in the player HUD until toggled off or the session ends.
- Stress, hunger and thirst come from `kora_core` metadata (`stress`, `hunger`, `thirst`).

## Vehicle panel

Speed is `GetEntitySpeed * 3.6` converted to the configured unit. Fuel is `GetVehicleFuelLevel`; vehicles that `kora_fuel:isElectricVehicle` reports as electric show a charge gauge. Headlights are off, low or high. The harness icon follows `Config.seatbelt.harnessIcon`.

While a `kora_lib` progress bar is shown in a vehicle, the gauge row lifts above it (`avoidProgressBar`). The gauge row's Anchor toggle in the editor keeps it near the bottom on foot and above the vehicle panel in a vehicle.

## Voice indicator

Shows talking state from `NetworkIsPlayerTalking`, which works with any Mumble-based voice resource. When `Config.voice.resource` exposes `getTalkingMode()`, the pill also shows the mode, signal and range.

## Assets

Seatbelt sounds are in `web/build/sounds` (sources in `web/public/sounds`). The square minimap mask is `stream/kora_hud_squaremap.ytd`, built by `tools/gen_minimap_ytd.py`.
