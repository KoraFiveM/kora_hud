---
title: Exports
sidebar_position: 5
---

# Exports

All exports are client side. There are no server exports.

## Visibility

```lua
exports.kora_hud:hide()      -- force-hide the HUD regardless of login state
exports.kora_hud:show()      -- clear the forced hide; login state still gates
exports.kora_hud:isVisible() -- boolean, what the HUD currently shows
```

`hide()` is an override: logging in while hidden keeps the HUD hidden until `show()`. `show()` does not force the HUD on; it is a no-op during character selection. While hidden by `hide()`, the radar is also held hidden when `Config.hud.hideMinimapWhenForcedHidden` is true (default).

## Minimap

```lua
exports.kora_hud:applyMinimapLayout() -- boolean
```

Re-applies the managed minimap layout (for resources that moved the minimap temporarily). Returns `false` when `Config.hud.minimapLayout.enabled` is false or the shape is `'stock'`.

## Layout

```lua
exports.kora_hud:getLayout()
```

Returns the player's saved layout, already validated. Intended for `kora_chat` at start-up. The shape is internal to the HUD and the editor.

## UI element registry

Used to make an element of your own resource appear in the `/ui` editor. See [UI editor](./ui-editor.md) for the definition fields and the events.

| Export | Returns | Notes |
| --- | --- | --- |
| `registerUiElement(def)` | `true`, or `false, reason` | Fails when the editor is disabled, `Config.uiEditor.allowExternal` is false, the id is invalid, taken or built in, or limits are reached (12 elements per resource, 32 total). |
| `updateUiElement(id, patch)` | `true`, or `false, reason` | Only `rect` and `defaultOffset` can be updated, only by the owner. |
| `unregisterUiElement(id)` | boolean | Owner only. |
| `getUiLayout(id)` | layout table or `nil` | The validated layout `{ x, y, placed, scale, hidden, settings }`. |

The owner is always the calling resource; it cannot be passed as an argument.
