---
title: "UI element registry"
sidebar_position: 4
---


# UI element registry

kora_hud hosts the `/ui` editor (it draws the panel and an outline proxy for every element), but most elements live in OTHER resources' own NUI frames — kora_chat's composer, kora_inventory's window. A host cannot move DOM inside another resource's frame, so each owner registers a small description here, and kora_hud tells the owner where to put it through the local client event `kora_hud:ui:apply(owner, id, layout, mode)` (`mode` is `'saved'` on registration, `'preview'` while dragging, or `'reset'` after `/hudlayoutreset`). Owners only turn `{ x, y, scale, hidden, settings }` into CSS; no layout math is duplicated per owner.

Namespace: `exports.kora_hud` · Source: `client/uiregistry.lua, client/hud.lua`

## How it works

Every value arriving from another resource's Lua (`registerUiElement`) or from this resource's own browser page (a saved/preview layout) is treated as untrusted input: every string is length-capped, every number range-checked, every collection size-capped, and setting values are checked against the owner's own declared schema (`HudUi.sanitiseDef`/`HudUi.cleanSettings`). `GetInvokingResource()` is the only source of truth for `owner` — it is never an argument, so one resource cannot register or modify another's element.

## Adding your own draggable element to /ui

1. **Register once at resource start** — Call `registerUiElement` with your element's id, initial rect and any per-element settings you want players to control.
2. **Listen for kora_hud:ui:apply** — AddEventHandler the local event; apply `{ x, y, scale, hidden, settings }` (viewport-fraction offsets relative to your `rect`, not absolute positions) as CSS on your own NUI frame.
3. **Enter/exit focus-sharing** — Listen for `kora_hud:ui:editing(true/false)` to hide your own interactive UI (e.g. a chat input box) and show a lightweight preview while the editor has focus.
4. **Unregister on stop (optional)** — Not required — `onClientResourceStop` drops your elements automatically — but call `unregisterUiElement` if you want to remove one element without stopping.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Owner | The resource that registered an element, taken from `GetInvokingResource()`, never a caller-supplied argument. |
| Built-in section | kora_hud's own four sections (`gauges`, `vehicle`, `identity`, `status`) plus `minimap` — these ids are reserved and `registerUiElement` refuses them. |
| kora_hud:ui:apply(owner, id, layout, mode) | Local client event an owner listens to; fired on registration (`mode = 'saved'`), during a drag (`'preview'`), and after a layout reset (`'reset'`). |
| kora_hud:ui:editing(open) | Local client event fired when the `/ui` editor opens or closes, so owners can release focus-sensitive UI of their own while it is open. |

## Setting types for `def.settings`

Each entry becomes one control in the editor under your element; `HudUi.layoutFor` always returns a value for every declared setting (the saved value or its `default`).

| Option | Type | Description |
| --- | --- | --- |
| `toggle` | boolean | A simple on/off switch. `default` is a boolean. |
| `range` | number | `min`/`max` required (max > min); optional `step` (quantises the value) and `unit`/`zeroLabel` for display. |
| `select` | string | Up to 12 `{ value, label? }` options; `default` must be one of them or the first option is used. |

## Functions

Four exports: one write per lifecycle stage (register/update/unregister) plus one read.

### `exports.kora_hud:registerUiElement(def)`

Registers (or, called again by the same resource, replaces) one element of the invoking resource in the unified `/ui` editor. The owner is always `GetInvokingResource()` — a resource can neither claim nor change another resource's element. Refused while `Config.uiEditor.enabled` or `.allowExternal` is `false`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `def` | table | `{ id, label?, group?, rect, defaultOffset?, origin?, movable?, scalable?, hideable?, scaleMin?, scaleMax?, settings? }`. `id` must match `^%a[%w_]*$`, ≤32 chars, and not collide with a built-in HUD section (`gauges`, `vehicle`, `identity`, `status`) or `minimap`. `rect = { x, y, w, h }` (viewport fractions, 0–1, `w`/`h` > 0) is the element's own zero-point rectangle. `settings` is up to 8 entries of `{ key, label?, description?, type: 'toggle'\|'range'\|'select', default, min?, max?, step?, unit?, zeroLabel?, options? }` (up to 12 options per `select`). Limits: 12 elements per owner, 32 total. |

**Returns**

- **ok** — `true` on success, or `false, reason` (`'invalid id'`, `'id taken'`, `'id is a built-in HUD section'`, `'too many elements for this resource'`, `'too many elements'`, `'ui editor disabled'`, `'unknown owner'`, or a `rect`/shape validation message).

**Example**

```lua
exports.kora_hud:registerUiElement({
    id = 'myChatBox', label = 'Chat', group = 'Chat',
    rect = { x = 0.01, y = 0.70, w = 0.30, h = 0.25 },
    origin = 'left bottom', hideable = true,
    settings = { { key = 'opacity', label = 'Opacity', type = 'range', min = 0.2, max = 1, step = 0.05, default = 0.9 } },
})
```

**Representative console output**

```text
true. The element appears in `/ui`; this resource immediately receives `kora_hud:ui:apply(owner, 'myChatBox', layout, 'saved')` with this player's already-saved position.
```

### `exports.kora_hud:updateUiElement(id, patch)`

Owner-only partial update of an element's measured geometry (its own `rect`/`defaultOffset`, not the player's saved layout) — for an element whose on-screen size changes at runtime.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | An id previously registered by the invoking resource. |
| `patch` | table | `{ rect? , defaultOffset? }`; at least one must be present and valid. |

**Returns**

- **ok** — `true` on success.
- **err** — set on failure: `'not registered by this resource'`, `'patch must be a table'`, `'nothing to update'`, or `'ui editor disabled'`.

**Example**

```lua
exports.kora_hud:updateUiElement('myChatBox', { rect = { x = 0.01, y = 0.60, w = 0.30, h = 0.35 } })
```

**Representative console output**

```text
true
```

### `exports.kora_hud:unregisterUiElement(id)`

Removes an element the invoking resource registered. (A stopped resource's elements are also dropped automatically via `onClientResourceStop` — this export is for a resource that wants to remove just one element while staying up.)

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | An id previously registered by the invoking resource. |

**Returns**

- **removed** — `true` if it existed and belonged to this resource, otherwise `false`.

**Example**

```lua
exports.kora_hud:unregisterUiElement('myChatBox')
```

**Representative console output**

```text
true
```

### `exports.kora_hud:getUiLayout(id)`

The fully-resolved layout for one registered element — the same shape an owner receives via `kora_hud:ui:apply`, with every setting defaulted. Useful to read a layout again without waiting for the next apply event.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | A registered element id (any owner, not just the invoker). |

**Returns**

- **layout** — `{ x, y, placed, scale, hidden, settings }`, or `nil` if the id is not registered or the editor is disabled.

**Example**

```lua
local layout = exports.kora_hud:getUiLayout('myChatBox')
if layout and layout.hidden then hideMyChatBox() end
```

**Representative console output**

```text
`{ x = 0, y = 0, placed = false, scale = 1, hidden = false, settings = { opacity = 0.9 } }`
```

## Limits and related APIs

12 elements per owning resource, 32 total across all resources, 8 settings per element, 12 options per `select` setting. Hiding is only possible for an element whose `hideable` was `true` at registration. `settings` values for an owner that is not currently running are preserved as opaque scalars (`HudUi.preserveSettings`) rather than validated against a schema that cannot be read.

## Related guides

- [Layout](./layout.md)
- [Minimap](./minimap.md)
- [HUD visibility](./visibility.md)
