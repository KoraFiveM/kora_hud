---
title: Installation
sidebar_position: 2
---

# Installation

## Dependencies

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

## Start order

```cfg
ensure kora_lib
ensure kora_theme
ensure kora_core
ensure kora_fuel
ensure kora_hud
```

## Web build

`web/build` is committed and served statically (`ui_page 'web/build/index.html'`), so there is no build step on the server. The source is in `web/` (`pnpm` project).

## Standalone stub adapter

`client/bridge/stub.lua` is an alternative adapter with mock data (cash 500, bank 5000, full hunger and thirst, slow drain). It is not listed in `fxmanifest.lua`; to use it you must edit the manifest yourself, replace `client/bridge/kora_core.lua` with it and set `Config.bridge.adapter = "stub"` for consistency. Note that the manifest still declares `dependency 'kora_core'` and `client/stress.lua` still calls `exports.kora_core:getPlayerData` (failures are caught), so removing kora_core also means editing those. `Config.bridge.adapter` is informational: which adapter loads is decided only by `client_scripts`. See [Bridge](./bridge.md).

## Optional FFT hooks

`fft_hooks.lua` is inert unless the convar `fft_kora_hooks` is `true`. See [Events](./events.md#fft-test-hooks).
