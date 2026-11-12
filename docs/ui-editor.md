---
title: UI editor
sidebar_position: 9
---

# UI editor

Players arrange their HUD with `/ui` (aliases from `Config.uiEditor.aliases`, default `/hudsettings`) or `/hudlayout`. All of these open the same editor. With `Config.uiEditor.enabled = false` the original editor opens instead: only the four HUD sections and the chat input can be moved, with no per-element hiding and no elements from other resources.

## Using the editor

The editor is an explicit mode: it takes NUI focus and dims the screen. Each section gets Move, Resize and Align controls.

- Move by dragging. Hold Control to snap to a 5% viewport grid; hold Shift to snap to 45 degree angles.
- Resize left or right. HUD sections and the chat input scale 75%-150%; registered elements use their own range (50%-200% at most).
- Align cycles left, centre and right for the contents of a section.
- The gauge row has an Anchor toggle.
- With the unified editor, pick an element from the dropdown or click it, then use Visible (when hiding is allowed and the element supports it), Size, the element's own settings and Reset for that element. Save, Cancel (Escape) and Reset all apply to the whole layout.
- A "Minimap only in vehicle" switch is shown when `Config.hud.minimapVehicleOnly.allowPlayerChange` is on.

Confirm saves; Cancel restores what was saved when the editor opened. Dragging only previews; nothing is written until Confirm. `/hudlayoutreset` (or `/uireset`) deletes the saved layout without opening the editor, so a player can recover from an unreachable placement.

With `Config.layout.movable = false` nothing can be moved and saved layouts are ignored.

## Storage

The layout is saved as JSON in the player's own client KVP under `Config.layout.kvpKey` (default `kora_hud:layout`). It is per player and per machine; there is no database column and no server round trip. Two more KVP keys store the minimap choice: `kora_hud:minimapHidden` (`hidden` or `visible`) and `kora_hud:minimapOnFoot` (`1`).

Offsets are fractions of the viewport, not pixels, and each section's default corner is its zero point. The stored value is treated as untrusted on read and validated and clamped on write: offsets are bounded per section, scales are clamped, at most 48 entries are accepted and the blob is limited to 16384 bytes (a larger layout is refused with an error notification).

## Registering your own element

Elements live in other resources' NUI frames, so the owner registers a description and kora_hud tells it where to place the element through `kora_hud:ui:apply`. Owners only convert the layout to CSS.

```lua
-- Add the handler BEFORE registering: registration answers immediately.
AddEventHandler('kora_hud:ui:apply', function(owner, id, layout, reason)
    if owner ~= GetCurrentResourceName() or id ~= 'myElement' then return end
    -- layout = { x, y, placed, scale, hidden, settings = { ... } }, already validated
end)

local function register()
    exports.kora_hud:registerUiElement({
        id = 'myElement', label = 'My element', group = 'My resource',
        rect = { x = 0.4, y = 0.1, w = 0.2, h = 0.1 },  -- zero point, viewport fractions
        defaultOffset = { x = 0, y = 0 },               -- optional
        origin = 'center top', movable = true, scalable = true, hideable = true,
        scaleMin = 0.75, scaleMax = 1.25,
        settings = {
            { key = 'compact', label = 'Compact', type = 'toggle', default = false },
        },
    })
end

register()
AddEventHandler('kora_hud:ui:ready', register) -- kora_hud (re)started
```

### Definition fields

| Field | Notes |
| --- | --- |
| `id` | Required. Letters, digits and underscore, starting with a letter, up to 32 characters. `v`, `minimapVehicleOnly`, `minimap` and the built-in section ids (`gauges`, `vehicle`, `identity`, `status`) are refused. |
| `label`, `group` | Display text, capped at 32 and 24 characters. Group defaults to `Other`. |
| `rect` | Required `x`, `y`, `w`, `h` in 0-1 viewport fractions, with positive size. |
| `defaultOffset` | Optional `x`, `y` in -1 to 1. |
| `origin` | `left`, `center` or `right` plus `top`, `center` or `bottom`, separated by a space. Default `left top`. |
| `movable`, `scalable` | Default `true`. |
| `hideable` | Default `false`. |
| `scaleMin`, `scaleMax` | Clamped to 0.5-2.0; the range always includes 1.0. Defaults 0.75 and 1.5. |
| `settings` | Up to 8, each with `key`, `label`, optional `description` and `type`: `toggle` (`default`), `range` (`min`, `max`, `step`, `default`, `unit`, `zeroLabel`) or `select` (`options`, up to 12, `default`). Invalid settings are dropped silently. |

`kora_hud:ui:editing` tells owners when the editor opens or closes. Registrations belong to the calling resource and are dropped when it stops; its saved layout is kept. Only `rect` and `defaultOffset` can be changed later with `updateUiElement`. See [Exports](./api/index.md) and [Events](./events.md).
