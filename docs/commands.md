---
title: Commands
sidebar_position: 4
---

# Commands

All commands are client commands registered with `RegisterCommand(..., false)` (no ACE restriction).

| Command | Registered by | Behaviour |
| --- | --- | --- |
| `/hudlayout` (`Config.layout.command`) | `client/hud.lua` | Opens the layout editor. With `Config.layout.movable = false` it reports that moving is disabled. |
| `/ui` (`Config.uiEditor.command`) and aliases (`Config.uiEditor.aliases`, default `hudsettings`) | `client/hud.lua` | Same editor. Registered only while `Config.uiEditor.enabled` and `Config.layout.movable` are on. Names must match letters, digits and underscore, up to 32 characters. |
| `/hudlayoutreset` | `client/hud.lua` | Deletes the saved layout and notifies "HUD layout reset to defaults.". |
| `/uireset` (`Config.uiEditor.resetCommand`) | `client/hud.lua` | Same as `/hudlayoutreset`; registered when the editor is enabled. |
| `/id` | `client/hud.lua` | Toggles showing your server ID in the HUD. Session only, not saved. |
| `/minimap` (`Config.hud.minimapToggle.command`) | `client/hud.lua` | Toggles your minimap. When `Config.hud.minimapToggle.enabled` is false it only notifies that the toggle is disabled. |
| `/cash`, `/bank` | `client/compat.lua` | Show your own balance as a notification. See [Compatibility](./compatibility.md). |
| `/hud_toggleseatbelt` | bridge adapter | With the `kora_core` adapter it triggers `kora_utils:client:toggleSeatbelt`. With the stub adapter it toggles a local placeholder state. |
| `/hudtest_cash`, `/hudtest_bank`, `/hudtest_stress` | `client/bridge/stub.lua` | Set mock values (stress clamped to 0-100). Exist only with the stub adapter. |

`Config.layout.command`, the `/ui` names, `Config.uiEditor.resetCommand` and `Config.hud.minimapToggle.command` are read at resource start; restart the resource after changing them.

## Key bindings

| Binding | Default key | Notes |
| --- | --- | --- |
| "Toggle minimap" (`kora_hud_minimap`) | unbound (`Config.hud.minimapToggle.defaultKey`) | Registered through `Kora.keybind`; players rebind in Settings > Key Bindings. |
| "Toggle seatbelt (qb-hud stub bridge)" (`hud_toggleseatbelt`) | `B` | Registered only by the stub adapter. With the `kora_core` adapter the `B` key belongs to `kora_utils`. |
