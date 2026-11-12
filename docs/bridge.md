---
title: Bridge
sidebar_position: 10
---

# Bridge

The HUD never calls a framework directly. `client/hud.lua` only uses a global `HudBridge` table that an adapter file assigns. The contract is documented in `shared/bridge.lua`.

## Contract

```lua
---@class KoraHudBridge
---@field getSnapshot fun(): KoraHudBridgeSnapshot                        -- required
---@field getSeatbelt (fun(): boolean) | nil
---@field getHarness (fun(): boolean) | nil
---@field onChange (fun(handler: fun(snapshot: KoraHudBridgeSnapshot)): nil) | nil  -- else polled
---@field isLoggedIn (fun(): boolean) | nil                               -- else always visible
---@field onLoginChange (fun(handler: fun(loggedIn: boolean)): nil) | nil

---@class KoraHudBridgeSnapshot
---@field job { name: string, label: string, grade: integer, gradeLabel: string, onDuty: boolean }
---@field gang { name: string, label: string, grade: integer, gradeLabel: string } | nil
---@field cash number
---@field bank number
---@field hunger number     -- 0-100
---@field thirst number     -- 0-100
---@field stress number     -- 0-100
---@field seatbelt boolean
---@field status { name: string, severity: integer|nil }[] | nil
```

Without `onChange` the HUD polls `getSnapshot` every `Config.poll.bridgeInterval`.

## Shipped adapters

| File | Loaded by default | Behaviour |
| --- | --- | --- |
| `client/bridge/kora_core.lua` | yes | Reads `exports.kora_core:getPlayerData()`, pushes changes through `onPlayerDataChange` on `money`, `job`, `gang` and `metadata`, coalescing bursts into one rebuild per frame. Login state comes from the `kora_core:loggedIn` state bag, gated by `kora_multichar:mode`. If player data does not appear it retries up to 3 rounds of 200 frames, calling `requestResync` between rounds. Cash is read from the `kora_core:money:cash` state bag. Defaults when data is missing: job `unemployed` / `Civilian`, hunger and thirst 100, stress 0. Seatbelt and harness come from `kora_utils` events. |
| `client/bridge/stub.lua` | no | Mock data and the `hudtest_*` commands. Own seatbelt placeholder on `B`. No login gating, so the HUD is always visible. |

## Writing an adapter

Create `client/bridge/<name>.lua` that assigns the contract above, list it in `fxmanifest.lua` in place of the current adapter and update `Config.bridge.adapter`. `client/hud.lua`, `client/vehicle.lua` and `client/voice.lua` need no changes. Status effects should come from `Kora.status.getActive()` wrapped in `pcall`, as both shipped adapters do.
