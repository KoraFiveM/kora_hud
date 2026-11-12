---
title: Configuration
sidebar_position: 6
---

# Configuration

All options are in `config.lua`. Options marked **live** are registered with `kora_lib`'s config descriptors and are read at use time; others are read when the resource starts (or, for `Config.stress` and `Config.seatbelt.sound`, each time they are used, as noted). Where an option has no descriptor it is a plain value. Descriptors are optional: with an older `kora_lib` the plain defaults apply.

## `Config.hud`

| Option | Default | Notes |
| --- | --- | --- |
| `dynamic` | `false` | Hide gauges while at their neutral value (full health/stamina/hunger/thirst/fuel, empty armour/stress). |
| `elements.mic` `cash` `bank` `hungerThirst` `stamina` `stress` `vehicle` | all `true` | Per-element switches. Health, armour, job and gang cannot be switched off (dynamic mode can still hide health/armour while neutral). Switching `stamina` or `vehicle` off also stops the matching subscription or sampling; `mic` stops voice sampling. |
| `avoidProgressBar` | `true` (live) | In a vehicle, lift the gauge row above a `kora_lib` progress bar. |
| `avoidHarnessBar` | `false` (live) | Also lift above the race harness attach/remove bar. |
| `money.scrollAccounts` | `true` | Show one account at a time. Only cycles when both `elements.cash` and `elements.bank` are on; otherwise the enabled account is shown permanently. |
| `money.scrollAccountsTime` | `5000` | Milliseconds each account is shown. |
| `minimap` | `'vehicle'` | `'always'` (never touch `DisplayRadar`), `'vehicle'`, `'never'`. |
| `minimapToggle.enabled` | `true` (live) | Player minimap toggle. |
| `minimapToggle.command` | `'minimap'` | Registered at start. |
| `minimapToggle.defaultKey` | `''` | Unbound by default. Registered at start. |
| `minimapToggle.remember` | `true` (live) | Save the choice in client KVP. |
| `minimapToggle.defaultVisible` | `true` (live) | `false` = start hidden until toggled. |
| `minimapToggle.allowOnFoot` | `true` (live) | Let a player show the minimap on foot when the mode is vehicle only. |
| `minimapVehicleOnly.default` | `false` (live) | Server default for "Minimap only in vehicle". Effectively on when `minimap` is `'vehicle'`. |
| `minimapVehicleOnly.allowPlayerChange` | `true` (live) | `false` hides the switch and forces the default. Also forced while `Config.layout.movable` is false. |
| `hideMinimapWhenForcedHidden` | `true` (live) | Keep the radar hidden while another resource has called `hide()`. |
| `hideOnPauseMenu` | `true` (live) | Hide the whole HUD while the pause menu or full map is open. |
| `speedUnit` | `'kmh'` (live) | `'kmh'` or `'mph'`. Any other value behaves as `'kmh'`. |

`Config.hud.minimapLayout` is documented on the [Minimap](./api/minimap.md) page.

## `Config.layout`

| Option | Default | Notes |
| --- | --- | --- |
| `movable` | `true` | `false` pins the layout for everyone: no editor, saved layouts ignored. |
| `command` | `'hudlayout'` | Command that opens the editor. |
| `kvpKey` | `'kora_hud:layout'` | Client KVP key holding the saved layout JSON. |

## `Config.uiEditor`

| Option | Default | Notes |
| --- | --- | --- |
| `enabled` | `true` | Unified `/ui` editor. When off, `/hudlayout` opens the original editor (HUD sections and chat input only, no hiding, no other resources). |
| `command`, `aliases`, `resetCommand` | `'ui'`, `{ 'hudsettings' }`, `'uireset'` | Registered at start. |
| `allowHide` | `true` (live) | Players may hide elements that support it. |
| `allowExternal` | `true` | Accept elements registered by other resources. |
| `minimap` | `true` (live) | Players may move and resize the minimap (needs `minimapLayout.enabled` and a shape other than `'stock'`). |
| `previewInterval` | `100` | Milliseconds between live previews sent to owners; clamped to 50-1000 when sent to the page. |

## `Config.seatbelt`

| Option | Default | Notes |
| --- | --- | --- |
| `harnessIcon` | `'attached'` (live) | `'attached'`, `'always'` (dimmed when not attached) or `'off'`. |
| `sound.enabled` | `true` (live) | Buckle/unbuckle sounds for the local player. |
| `sound.volume` | `0.5` (live) | 0.0-1.0; applies to the `nui` backend only. A volume of 0 plays nothing. |
| `sound.backend` | `'nui'` (live) | `'nui'` plays the bundled WAVs from the HUD page; `'native'` uses `PlaySoundFrontend` at a fixed volume. |
| `sound.buckleFile`, `sound.unbuckleFile` | `seatbelt_buckle.wav`, `seatbelt_unbuckle.wav` | Files in `web/build/sounds`. New files must be listed in `fxmanifest.lua` `files`. |
| `sound.native.buckle`, `sound.native.unbuckle` | `SELECT`, `BACK` in `HUD_FRONTEND_DEFAULT_SOUNDSET` | Used by the `native` backend. |

A sound plays only when the seatbelt state actually changes and the player is in a vehicle; entering or leaving a vehicle is silent. The state comes from the `seatbelt:client:ToggleSeatbelt` event.

## `Config.bridge`

`adapter = "kora_core"`. Informational only; the loaded adapter is whichever file `fxmanifest.lua` lists. See [Bridge](./bridge.md).

## `Config.voice`

| Option | Default | Notes |
| --- | --- | --- |
| `enabled` | `true` | Master switch for the mic indicator and its sampling. |
| `resource` | `'kora_voice'` | Resource asked for `getTalkingMode()`, which should return `index`, `name`, `label` and `range`. Missing or failing exports fall back to the mic-only icon. An empty value disables the lookup. |
| `interval` | `200` | Milliseconds between mic samples. Sampling only runs while the HUD is visible and `elements.mic` is on. |

## `Config.poll`

Each value is a ceiling on how often a channel can send, using a leading-edge throttle: the first change goes out immediately and only further changes inside the interval are coalesced.

| Option | Default | Range | Channel |
| --- | --- | --- | --- |
| `vitalsInterval` | `150` | 50-5000 | Health, armour, stamina, talking (`kora_hud:vitals`). |
| `playerInterval` | `100` | 50-5000 | Job, gang, money, needs, status (`kora_hud:update`). |
| `vehicleInterval` | `250` | 50-5000 | Speed, fuel, engine, headlights (`kora_hud:vehicle`), only while in a vehicle. |
| `bridgeInterval` | `500` | 50-10000 | Fallback polling for adapters with no `onChange` (the `kora_core` adapter pushes instead). |
| `minimapInterval` | `250` | - | How often `SETUP_HEALTH_ARMOUR` is re-issued to hide the stock health/armour cluster. `0` restores per-frame behaviour. |

## `Config.stress`

See [Stress](./api/stress.md).
