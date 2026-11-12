---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora HUD is the player HUD: health/armour/stamina rings, cash/bank, hunger/thirst/stress, job/gang, the mic indicator, vehicle telemetry (speed/fuel/engine/headlights/seatbelt), the minimap layout, and the unified `/ui` layout editor other resources plug their own elements into. It is client-only — there is no server_scripts entry and no server export at all. It reads real player data from kora_core through a small adapter (client/bridge/kora_core.lua) rather than owning any state of its own.

## Dependencies and load order

- `fxmanifest.lua` declares four hard dependencies, started by FiveM before kora_hud regardless of server.cfg order: `kora_theme`, `kora_lib`, `kora_core`, `kora_fuel`.
- `kora_fuel` is only used for one pcall'd export, `exports.kora_fuel:isElectricVehicle(vehicle)` (client/vehicle.lua), to classify a vehicle's gauge as `fuel` or `charge`. A missing/restarting kora_fuel just makes that one sample fall back to `fuel`.
- kora_lib is loaded twice over: as a normal `dependency` and again as `shared_script '@kora_lib/init.lua'` ahead of `config.lua`, so `Kora.config.*` descriptors exist while config.lua runs (see "Config toggles" below).
- `kora_core` supplies the real job/gang/money/hunger/thirst/stress/metadata data through `client/bridge/kora_core.lua` (`exports.kora_core:getPlayerData()`, `:onPlayerDataChange()`, `:requestResync()`). Swapping `Config.bridge.adapter` away from `"kora_core"` and the client_scripts entry back to `client/bridge/stub.lua` runs the HUD against mock data with no framework at all.
- `kora_voice` (named by `Config.voice.resource`, default `"kora_voice"`) is an **optional** integration: client/voice.lua calls `exports[Config.voice.resource]:getTalkingMode()` inside a `pcall`, so a missing or differently-named voice resource only loses the proximity-range label, never the mic icon itself (which comes straight from the `NetworkIsPlayerTalking` native).
- `kora_utils` (not declared as a dependency) owns the real seatbelt and race-harness mechanics. kora_hud only listens for the local client events `seatbelt:client:ToggleSeatbelt` and `seatbelt:client:ToggleHarness` (see Seatbelt/harness integration below) — if nothing ever fires them, the seatbelt icon simply never changes from unbuckled.

## Install Kora HUD

1. **Place the folder** — Put `kora_hud` in your resources directory. Keep the folder name: `provide 'qb-hud'` in the manifest makes `exports['qb-hud']` resolve to this resource for legacy callers; the real export table is `exports.kora_hud`.

2. **Start order** — Start the dependencies first, then kora_hud. Starting kora_voice/kora_utils before or after kora_hud does not matter — both integrations are pcall-guarded and re-subscribe on their own `onClientResourceStart`.

   ```bash title="server.cfg"
   ensure kora_theme
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_fuel
   ensure kora_hud
   # kora_voice and kora_utils are optional integrations (see Voice and Seatbelt
   # below) — kora_hud degrades gracefully if either is absent or starts later.
   ensure kora_voice
   ensure kora_utils
   ```

3. **Confirm it is up** — In-game, the gauges, job/cash pills and mic icon should appear once logged into a character. `/hudlayout` (or `/ui`) opens the layout editor; `/id` toggles a player-id badge for yourself.

## What the manifest declares

```text title="fxmanifest.lua (excerpt)"
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_hud'
provide 'qb-hud'

dependency 'kora_theme'
dependency 'kora_lib'
dependency 'kora_core'
dependency 'kora_fuel'
```

- No `server_scripts` entry exists anywhere in the manifest — this resource is 100% client + shared config.
- `ui_page 'web/build/index.html'` plus a `files` block publishing `web/build/index.html`, `web/build/assets/**/*` and `web/build/sounds/*.wav`. `web/build` is the committed build artifact; there is no build step at resource start.
- client_scripts load `@kora_theme/client/bridge.lua`, then `client/bridge/kora_core.lua` (the adapter), then `client/voice.lua`, `client/vehicle.lua`, `client/seatbelt_sound.lua`, `client/minimap.lua`, `client/stress.lua`, `client/compat.lua`, `client/uiregistry.lua`, and finally `client/hud.lua` — the one file that owns NUI focus and every `SendNUIMessage`/`RegisterNUICallback` call. The order matters: `HudBridge` must exist before anything references it, and `uiregistry.lua` (the `/ui` element registry) must exist before `hud.lua`, which owns the editor.

## If the HUD never appears

- Check the bridge: with `Config.bridge.adapter = "kora_core"`, the HUD stays hidden until `LocalPlayer.state['kora_core:loggedIn']` is `true` and no `kora_multichar` cinematic mode state bag is set (character select / spawn carousel / scene-studio preview all count as "cinematic"). It also waits for `exports.kora_core:getPlayerData()` to return non-nil — a kora_core still mid-boot nudges a resync and retries (bounded, see client/bridge/kora_core.lua).
- If using the stub bridge instead (`Config.bridge.adapter` changed away from `"kora_core"` AND `fxmanifest.lua`'s client_scripts changed to load `client/bridge/stub.lua`), the HUD has no login concept at all and is always visible — `HudBridge.isLoggedIn`/`onLoginChange` are simply absent from the stub, and `client/hud.lua` treats that as "always shown".
- Another resource may be holding the HUD forced-hidden via `exports.kora_hud:hide()` (for example a clothing menu) and never calling `:show()` again — check `exports.kora_hud:isVisible()`.
- If only the minimap is wrong, see `Config.hud.minimap` / `Config.hud.minimapLayout` below before touching anything else; kora_hud repositions and re-masks the stock radar components and can fight another resource doing the same thing.

## Dependencies (manifest and runtime)

Declared with `dependency` in `fxmanifest.lua` (the resource does not start without them):

| Resource | Used for |
| --- | --- |
| `kora_theme` | Theme delivery to the NUI (`@kora_theme/client/bridge.lua`). |
| `kora_lib` | `Kora.cache` (health, armour, stamina, ped, vehicle, weapon), `Kora.notify`, `Kora.keybind`, `Kora.status`, `Kora.progressbar`, `Kora.config`. Loaded through `@kora_lib/init.lua`. |
| `kora_core` | Player data (`getPlayerData`, `onPlayerDataChange`, `requestResync`) through the shipped bridge adapter, and the metadata that stress is written to. |
| `kora_fuel` | `isElectricVehicle` export, used to show charge instead of fuel. Failures are caught and the panel falls back to fuel. |

Used at runtime but not declared in the manifest (all optional, calls are guarded):

| Resource | Used for |
| --- | --- |
| `kora_utils` | Owns the seatbelt and race harness. The HUD listens to `seatbelt:client:ToggleSeatbelt` / `ToggleHarness` and `hud_toggleseatbelt` forwards to `kora_utils:client:toggleSeatbelt`. |
| `kora_multichar` | Publishes the `kora_multichar:mode` state bag that keeps the HUD hidden during selection and spawn cinematics. |
| `Config.voice.resource` (default `kora_voice`) | Optional `getTalkingMode()` export. |
| `kora_chat` | Receives the saved chat composer layout and can register elements. |

## Web build

`web/build` is committed and served statically (`ui_page 'web/build/index.html'`), so there is no build step on the server. The source is in `web/` (`pnpm` project).

## Standalone stub adapter

`client/bridge/stub.lua` is an alternative adapter with mock data (cash 500, bank 5000, full hunger and thirst, slow drain). It is not listed in `fxmanifest.lua`; to use it you must edit the manifest yourself, replace `client/bridge/kora_core.lua` with it and set `Config.bridge.adapter = "stub"` for consistency. Note that the manifest still declares `dependency 'kora_core'` and `client/stress.lua` still calls `exports.kora_core:getPlayerData` (failures are caught), so removing kora_core also means editing those. `Config.bridge.adapter` is informational: which adapter loads is decided only by `client_scripts`. See [Bridge](./bridge.md).

## Optional FFT hooks

`fft_hooks.lua` is inert unless the convar `fft_kora_hooks` is `true`. See [Events](./events.md#fft-test-hooks).
