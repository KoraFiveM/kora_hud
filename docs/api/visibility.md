---
title: "HUD visibility"
sidebar_position: 2
---


# HUD visibility

Three exports compose login state, the pause menu, resource-stop and any force-hide into one visibility flag sent to the NUI as `kora_hud:visibility`.

Namespace: `exports.kora_hud` · Source: `client/hud.lua`

## How it works

`refreshVisibility()` (internal) recomputes `visible` from `loggedIn`, `forcedHidden`, the pause-menu/map state (when `Config.hud.hideOnPauseMenu`), and whether this resource itself is stopping, then sends `kora_hud:visibility` only on an actual change. `hide`/`show` only ever touch the `forcedHidden` half of that computation.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Composed visibility | The single boolean the NUI receives — true only when every gate (logged in, not force-hidden, not paused) agrees. |

## Functions

Three client exports; no server-side equivalent exists.

### `exports.kora_hud:hide()`

Force-hides the whole HUD regardless of login state — for cutscenes, custom camera modes or a menu (kora_clothing uses this for its own menu). Stacks with nothing: a second `hide()` while already hidden is a no-op repeat.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
exports.kora_hud:hide()
```

**Representative console output**

```text
The HUD (and, if `Config.hud.hideMinimapWhenForcedHidden` is true, the minimap) disappears at once; `kora_hud:visibility(false)` is sent to the NUI.
```

### `exports.kora_hud:show()`

Clears a force-hide set by `hide()`. Does **not** force the HUD on — login state and every other hide reason (pause menu, logged out) still apply, so calling this during character select is a safe no-op.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
exports.kora_hud:show()
```

**Representative console output**

```text
The HUD reappears only if the player is otherwise eligible to see it (logged in, not paused, not in a cinematic).
```

### `exports.kora_hud:isVisible()`

Reports the composed visibility the NUI currently has — the same value last sent as `kora_hud:visibility`.

**Parameters**



**Returns**

- **visible** — boolean.

**Example**

```lua
if not exports.kora_hud:isVisible() then return end
```

**Representative console output**

```text
true / false
```

## Limits and related APIs

Client-only. `show()` cannot override a login-gated hide; there is no way to force the HUD to show while genuinely logged out.

## Related guides

- [Layout](./layout.md)
- [UI element registry](./ui-registry.md)
