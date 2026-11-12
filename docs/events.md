---
title: Events
sidebar_position: 7
---

# Events

`kora_hud` has no server scripts and registers no server events. Nothing here crosses to the server except the stress metadata update described on [Stress](./api/stress.md).

## Events raised by kora_hud (client local)

| Event | Arguments | When |
| --- | --- | --- |
| `kora_hud:ui:apply` | `owner`, `id`, `layout`, `reason` | To the owner of a registered element: on registration, while dragging in the editor (`'preview'`), after save or cancel (`'saved'`) and on reset (`'reset'`). `layout` is `x`, `y`, `placed`, `scale`, `hidden`, `settings`. |
| `kora_hud:ui:ready` | none | After kora_hud (re)starts with the editor enabled; owners should register again. |
| `kora_hud:ui:editing` | `editing` (boolean) | The editor opened or closed. Owners close their own focused UI when it opens. |
| `kora_hud:client:stressGained` | `newStress` | After a stress gain, at most every 10 seconds, when `Config.stress.notify` is not false. |
| `kora_chat:setInputLayout` | layout table | Sent to `kora_chat` when it is started, to apply the saved chat composer layout. |

Handlers that error are caught and printed; they never abort the editor.

## Events the HUD listens to

| Event | Source | Effect |
| --- | --- | --- |
| `seatbelt:client:ToggleSeatbelt` | `kora_utils` or the stub adapter | Updates the seatbelt icon and plays the seatbelt sound. |
| `seatbelt:client:ToggleHarness` | `kora_utils` | Race harness attached flag (`kora_core` adapter). |
| `seatbelt:client:UseHarness` | `kora_utils` | Marks the harness progress bar so it does not lift the gauges unless `avoidHarnessBar` is on. |
| `playerSpawned`, `onClientResourceStart`, `onResourceStop` | FiveM | Re-apply the minimap mask and layout, restore stock state on stop. |
| `onClientResourceStop` | FiveM | Drops UI elements registered by the stopped resource (their saved layout is kept). |
| `hud:client:*`, `seatbelt:client:ToggleCruise` | other resources | qb-hud compatibility, see [Compatibility](./api/compat.md). |

## State bags read

| Key | Meaning |
| --- | --- |
| `kora_core:loggedIn` (player) | The HUD renders only while true. |
| `kora_multichar:mode` (player) | Any truthy value (a mode string) hides the HUD until cleared. |
| `kora_core:money:cash` (player) | Cash value; changes trigger a refresh. |
| `seatbelt`, `harness` (local player) | Initial seatbelt and harness state after a restart. |

## NUI callbacks

Registered on the HUD's own NUI frame and used only by its page:

| Callback | Purpose |
| --- | --- |
| `kora_hud:ready` | The page mounted; Lua replies and pushes the full initial state. |
| `kora_hud:uiPreview` | Live preview while dragging (editor open only). The minimap is applied on drop only. |
| `kora_hud:finishLayout` | Confirm or cancel the editor; only a confirmed layout is saved. |

Messages sent to the page (`SendNUIMessage` actions) include `kora_hud:config`, `kora_hud:vitals`, `kora_hud:update`, `kora_hud:vehicle`, `kora_hud:visibility`, `kora_hud:compat`, `kora_hud:layoutMode`, `kora_hud:layoutReset`, `kora_hud:uiElements`, `kora_hud:playerId` and `kora_hud:seatbeltSound`.

## FFT test hooks

`fft_hooks.lua` does nothing unless the convar `fft_kora_hooks` is `true`. When enabled it wraps `SendNUIMessage` to keep a bounded log (300 entries) of what was sent to the page and exports `fftVersion` and `fftAction`. `fftAction` only works when invoked by the resource named `fft` and a `fftSession` state bag is set; the supported actions are `state` and `log`. These are development hooks, not a public API.
