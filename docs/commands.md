---
title: "Commands"
sidebar_position: 4
---


# Commands

All commands are client commands (`RegisterCommand(..., false)`), registered on every client regardless of ACE — there is nothing server-side to restrict. Command names come from `Config.layout.command` / `Config.uiEditor` and can be changed per server.

## Built-in commands

### `/hudlayout`

Opens the layout editor: drag, resize and align HUD sections (and, with the unified editor enabled, every registered element and the minimap). No-ops if the HUD is hidden, the editor is already open, or `Config.layout.movable` is `false` (a notification explains it is disabled).

| Field | Details |
| --- | --- |
| Context | In-game · client command (`Config.layout.command`, default `hudlayout`) |
| Arguments | No arguments. |
| Access | Any player. |

**Example**

```text
/hudlayout
```

**Result**

The HUD gains NUI focus and shows drag handles; Confirm or Cancel release it.

### `/ui (aliases: /hudsettings)`

The same editor as `/hudlayout`, plus every element another resource registered through `registerUiElement` (kora_chat's composer, kora_inventory's window) and, if `Config.uiEditor.minimap` allows it, the minimap itself. Falls back to being unavailable (classic `/hudlayout` only) when `Config.uiEditor.enabled = false`.

| Field | Details |
| --- | --- |
| Context | In-game · client command (`Config.uiEditor.command`/`.aliases`, only registered when `Config.uiEditor.enabled`) |
| Arguments | No arguments. |
| Access | Any player. |

**Example**

```text
/ui
```

**Result**

Same editor UI, with additional draggable outlines for external elements.

### `/hudlayoutreset`

Deletes the saved layout KVP outright (not just a UI reset) and notifies every registered element owner. Does not require the editor to be open.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | Any player. |

**Example**

```text
/hudlayoutreset
```

**Result**

Notification "HUD layout reset to defaults."; every section and registered element returns to its default position.

### `/uireset`

Alias of `/hudlayoutreset` under the configurable name.

| Field | Details |
| --- | --- |
| Context | In-game · client command (`Config.uiEditor.resetCommand`, only when it differs from `hudlayoutreset`) |
| Arguments | No arguments. |
| Access | Any player. |

**Example**

```text
/uireset
```

**Result**

Same as `/hudlayoutreset`.

### `/minimap`

Toggles the player's own minimap visibility on top of `Config.hud.minimap`'s mode. Also bindable as a key (`Config.hud.minimapToggle.defaultKey`, unbound by default). No-ops (with a notification) if `Config.hud.minimapToggle.enabled` is `false`.

| Field | Details |
| --- | --- |
| Context | In-game · client command (`Config.hud.minimapToggle.command`, default `minimap`) |
| Arguments | No arguments. |
| Access | Any player. |

**Example**

```text
/minimap
```

**Result**

Notification "Minimap hidden."/"Minimap shown." (or "...but this server keeps it hidden." under `minimap = 'never'`).

### `/id`

Toggles a small badge showing your own server id to yourself (`kora_hud:playerId`). Session-only: never saved, so it never reappears after reconnecting.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | Any player. |

**Example**

```text
/id
```

**Result**

Your server id appears/disappears on your own screen.

## Stub-bridge-only dev commands

`client/bridge/stub.lua` (used only when `Config.bridge.adapter` and the manifest's client_scripts are switched away from the real `kora_core` adapter) additionally registers `hud_toggleseatbelt` (bound to `B` by default via `Kora.keybind`), `hudtest_cash <amount>`, `hudtest_bank <amount>` and `hudtest_stress <0-100>` — manual-test commands with no effect while the real `kora_core` adapter is active.

## Command summary (code-derived)


All commands are client commands registered with `RegisterCommand(..., false)` (no ACE restriction).

| Command | Registered by | Behaviour |
| --- | --- | --- |
| `/hudlayout` (`Config.layout.command`) | `client/hud.lua` | Opens the layout editor. With `Config.layout.movable = false` it reports that moving is disabled. |
| `/ui` (`Config.uiEditor.command`) and aliases (`Config.uiEditor.aliases`, default `hudsettings`) | `client/hud.lua` | Same editor. Registered only while `Config.uiEditor.enabled` and `Config.layout.movable` are on. Names must match letters, digits and underscore, up to 32 characters. |
| `/hudlayoutreset` | `client/hud.lua` | Deletes the saved layout and notifies "HUD layout reset to defaults.". |
| `/uireset` (`Config.uiEditor.resetCommand`) | `client/hud.lua` | Same as `/hudlayoutreset`; registered when the editor is enabled. |
| `/id` | `client/hud.lua` | Toggles showing your server ID in the HUD. Session only, not saved. |
| `/minimap` (`Config.hud.minimapToggle.command`) | `client/hud.lua` | Toggles your minimap. When `Config.hud.minimapToggle.enabled` is false it only notifies that the toggle is disabled. |
| `/cash`, `/bank` | `client/compat.lua` | Show your own balance as a notification. See [Compatibility](./api/compat.md). |
| `/hud_toggleseatbelt` | bridge adapter | With the `kora_core` adapter it triggers `kora_utils:client:toggleSeatbelt`. With the stub adapter it toggles a local placeholder state. |
| `/hudtest_cash`, `/hudtest_bank`, `/hudtest_stress` | `client/bridge/stub.lua` | Set mock values (stress clamped to 0-100). Exist only with the stub adapter. |

`Config.layout.command`, the `/ui` names, `Config.uiEditor.resetCommand` and `Config.hud.minimapToggle.command` are read at resource start; restart the resource after changing them.

## Key bindings

| Binding | Default key | Notes |
| --- | --- | --- |
| "Toggle minimap" (`kora_hud_minimap`) | unbound (`Config.hud.minimapToggle.defaultKey`) | Registered through `Kora.keybind`; players rebind in Settings > Key Bindings. |
| "Toggle seatbelt (qb-hud stub bridge)" (`hud_toggleseatbelt`) | `B` | Registered only by the stub adapter. With the `kora_core` adapter the `B` key belongs to `kora_utils`. |
