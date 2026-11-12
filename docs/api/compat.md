---
title: "Legacy compat events"
sidebar_position: 6
---


# Legacy compat events

Local client events kept for scripts written against the original qb-hud's event names. All of them are **presentation-only**: nothing here writes server state or kora_core metadata, and anything shown through `UpdateNeeds`/`UpdateStress` is overwritten the next time the real bridge adapter pushes a fresh `kora_hud:update`. Use the integration points in the Bridge adapter contract / Voice / Stress modules for anything that needs to persist.

Namespace: `client events` · Source: `client/compat.lua`

## How it works

Every handler mutates `HudCompat.state` and calls a shared `push()` that forwards the whole state object as one `kora_hud:compat` NUI message — there is no per-field NUI channel for compat data.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| HudCompat.state | `{ dynamicHealth, altitude, showSeatbelt, cruise, harness, nitrous: { level, active } }` — the whole compat overlay, re-sent in full on every change. |

## Functions

Nine `RegisterNetEvent` handlers (also reachable with plain `TriggerEvent` since they are local-only in practice).

### `RegisterNetEvent('hud:client:UpdateNeeds', function(hunger, thirst) end)`

Legacy qb-hud event. Overlays hunger/thirst on top of the current bridge snapshot **in the NUI's compat layer only** — it writes no server state or metadata, and is replaced by the next authoritative `kora_hud:update` push from the real bridge adapter.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `hunger` | number \| nil | Clamped 0-100; omit/`nil` to leave unchanged. |
| `thirst` | number \| nil | Clamped 0-100; omit/`nil` to leave unchanged. |

**Returns**

- **No return value.**

**Example**

```lua
TriggerEvent('hud:client:UpdateNeeds', 80, 65)
```

**Representative console output**

```text
The NUI compat overlay shows hunger 80 / thirst 65 until the next kora_core push overwrites it.
```

### `RegisterNetEvent('hud:client:UpdateStress', function(stress) end)`

Same display-only overlay behaviour as UpdateNeeds, for stress.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `stress` | number | Clamped 0-100. |

**Returns**

- **No return value.**

**Example**

```lua
TriggerEvent('hud:client:UpdateStress', 40)
```

**Representative console output**

```text
Stress ring shows 40 until the next authoritative push.
```

### `RegisterNetEvent('hud:client:UpdateNitrous', function(level, active) end)`

Sets the compat nitrous indicator (`HudCompat.state.nitrous`) and pushes `kora_hud:compat` right away.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `level` | number | Clamped 0-100. |
| `active` | any | Truthy = active. |

**Returns**

- **No return value.**

**Example**

```lua
TriggerEvent('hud:client:UpdateNitrous', 75, true)
```

**Representative console output**

```text
`kora_hud:compat` is sent with `nitrous = { level = 75, active = true }`.
```

### `RegisterNetEvent('hud:client:UpdateHarness', function(uses) end)`

Legacy "harness uses remaining" compat field (distinct from the real `seatbelt:client:ToggleHarness`/`HudBridge.getHarness` path used by the vehicle panel icon).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `uses` | number | Clamped 0-100. |

**Returns**

- **No return value.**

**Example**

```lua
TriggerEvent('hud:client:UpdateHarness', 2)
```

**Representative console output**

```text
`HudCompat.state.harness = 2`, pushed via `kora_hud:compat`.
```

### `RegisterNetEvent('hud:client:ToggleHealth', function() end)`

Flips one boolean presentation flag in `HudCompat.state` (`dynamicHealth`, `altitude`, `showSeatbelt` respectively) and pushes `kora_hud:compat`.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
TriggerEvent('hud:client:ToggleShowSeatbelt')
```

**Representative console output**

```text
`HudCompat.state.showSeatbelt` flips and the NUI compat layer re-renders accordingly.
```

### `RegisterNetEvent('seatbelt:client:ToggleCruise', function() end)`

Flips the compat `cruise` flag, same mechanism as the Toggle* events above.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
TriggerEvent('seatbelt:client:ToggleCruise')
```

**Representative console output**

```text
`HudCompat.state.cruise` flips.
```

### `RegisterNetEvent('hud:client:ShowAccounts', function(account) end)`

Shows a one-off notification of the player's own current balance (through `Kora.notify.send`) for `'cash'` or `'bank'` — reads the **live** bridge snapshot, ignoring any amount a caller might try to pass. Also registered directly as the commands `/cash` and `/bank`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `account` | 'cash' \| 'bank' | Which balance to announce. |

**Returns**

- **amount** — the floored current balance (also returned by the identical `HudCompat.showAccount` command handlers), or `nil` for an unknown account name.

**Example**

```lua
TriggerEvent('hud:client:ShowAccounts', 'cash')
```

**Representative console output**

```text
A notification "Cash — $500" (the player's real current cash from the bridge snapshot, not any value the caller supplied).
```

### `RegisterNetEvent('hud:client:LoadMap', function() end)`

Re-applies the minimap layout on demand — the net-event equivalent of `exports.kora_hud:applyMinimapLayout()`.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
TriggerEvent('hud:client:LoadMap')
```

**Representative console output**

```text
The minimap layout is reapplied if `minimapHooks.applyMinimap` is wired up.
```

## Common use cases

- Running an existing qb-hud-era script unmodified against kora_hud.
- A quick cash/bank balance notification via `/cash` or `/bank`.

## Limits and related APIs

Display-only: UpdateNeeds/UpdateStress values are clobbered by the next kora_core-driven `kora_hud:update`. Not a persistence API — see the Bridge adapter contract and Stress gain modules for the real paths.

## Related guides

- [Stress gain](./stress.md)

## Handled events and commands (code-derived)


kora_hud declares `provide 'qb-hud'` and handles the stock client events below. They are display only: they never write server state or metadata (stress gain from `client/stress.lua` is separate, see [Stress](./stress.md)).

| Event | Effect |
| --- | --- |
| `hud:client:UpdateNeeds` (`hunger`, `thirst`) | Overlays hunger and thirst (clamped 0-100) on the local snapshot until the next `kora_core` update replaces them. |
| `hud:client:UpdateStress` (`stress`) | Same overlay for stress. |
| `hud:client:UpdateNitrous` (`level`, `active`) | Stored and sent to the page as `kora_hud:compat`. |
| `hud:client:UpdateHarness` (`uses`) | Stored and sent to the page as `kora_hud:compat`. |
| `hud:client:ToggleHealth`, `ToggleAirHud`, `ToggleShowSeatbelt`, `seatbelt:client:ToggleCruise` | Toggle a flag sent to the page as `kora_hud:compat`. |
| `hud:client:ShowAccounts` (`account`) | Shows the player's own `cash` or `bank` balance as a `kora_lib` notification. Any amount passed is ignored. |
| `hud:client:LoadMap` | Re-applies the minimap layout. |

The shipped web build does not read `kora_hud:compat`, so the nitrous, harness, cruise, altitude, dynamic-health and seatbelt-visibility flags have no visible effect.

`/cash` and `/bank` show the balance from the authoritative snapshot. `hud:server:getMenu` and the `menu`, `dev` and `resethud` commands of stock qb-hud are not provided.
