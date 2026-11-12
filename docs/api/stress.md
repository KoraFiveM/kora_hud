---
title: "Stress gain"
sidebar_position: 8
---


# Stress gain

The one place kora_hud actively changes authoritative player state rather than only displaying it: it restores the qb-hud behaviour of gaining stress from fast driving and shooting, writing the new value back to kora_core through the same `QBCore:Server:SetMetaData` compat event any other resource would use (needs `Config.compat.clientMetadataKeys.stress = true` in kora_core, its default).

Namespace: `Config.stress` · Source: `client/stress.lua, config.lua (Config.stress)`

## How it works

Speed checks run on a worker thread started/stopped on kora_lib's `vehicle` cache enter/exit edges (so nothing polls while on foot) at `Config.stress.speed.interval` (default 10s); a qualifying check (speed ≥ `threshold` in `speed.unit`, driver-only if `driverOnly`, job not in `whitelistedJobs`) rolls a gain between `gainMin`/`gainMax`. Shooting checks run only while a weapon capable of firing is held (`Config.stress.shooting.enabled`, weapon group allow-list, not `whitelistedWeapons`), with a `chance`% roll per shot and a `cooldown` before the next can land. `Config.stress.enabled = false` turns the whole feature off; `Config.stress.notify = false` stops the `stressGained` event without affecting the metadata write itself.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| whitelistedJobs | Job names (default `{ 'police' }`) that never gain stress from either source. |
| whitelistedWeapons | Weapon hashes that never cause shooting stress, empty by default. |

## Functions

One local event other resources can listen to; the write itself goes to kora_core, not through any kora_hud export.

### `AddEventHandler('kora_hud:client:stressGained', function(newStress) end)`

Local client event fired by client/stress.lua whenever it just raised the player's own stress (fast driving or shooting), rate-limited to at most once per 10 seconds. Intended for a notification resource to show "You feel stressed" rather than for state.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `newStress` | number | The stress value just written (0-100), after this gain was applied. |

**Returns**

- **No return value.**

**Example**

```lua
AddEventHandler('kora_hud:client:stressGained', function(newStress)
    Kora.notify.send({ title = 'Stress', message = ('Stress is now %d%%'):format(newStress), type = 'info' })
end)
```

**Representative console output**

```text
Fires after a qualifying speeding/shooting check, at most once per 10 seconds.
```

## Limits and related APIs

Client-authoritative by design (the same trust model qb-hud used): a modified client could suppress its own stress gain. Only speed and shooting are covered — no other stress source is implemented here.

## Related guides

- [Legacy compat events](./compat.md)

## Rules and persistence


`client/stress.lua` raises the player's stress client-side, restoring the qb-hud behaviour. It runs only when `Config.stress.enabled` is not false. Config is read on every tick, so edits apply immediately.

### Rules

- **Speeding** (`Config.stress.speed`): while in a vehicle, every `interval` ms (minimum 500, default 10000) the speed is compared with `threshold` (default 180) in `unit` (`'kmh'` or `'mph'`). At or above it, stress rises by a random whole number between `gainMin` and `gainMax` (1 to 3). With `driverOnly` (default true) only the driver gains stress. The worker exists only while the player is in a vehicle.
- **Shooting** (`Config.stress.shooting`): while a firearm or throwable is held (pistol, SMG, rifle, MG, shotgun, sniper, heavy, thrown, stun gun weapon groups) and the player is not dead, shots are sampled. Each shot check succeeds with `chance` percent (default 50), then adds `gainMin` to `gainMax`, and waits at least `cooldown` ms (default 3000, minimum 100) before the next. Hashes in `whitelistedWeapons` never cause stress.
- **Job whitelist**: players whose job name is in `whitelistedJobs` (default `police`) never gain stress.
- Stress is capped at 100.

### Persistence

The new value is sent with `TriggerServerEvent('QBCore:Server:SetMetaData', 'stress', value)`, which is handled by `kora_core`'s compatibility layer, not by this resource. The `kora_core` setting `Config.compat.clientMetadataKeys.stress` must allow it (documented in code as enabled by default). The HUD then receives the new value through the normal metadata update. Because the client computes and sends the value, stress is client-authoritative.

If `Config.stress.notify` is not false, `kora_hud:client:stressGained` is raised locally with the new value, at most every 10 seconds, for notification resources. kora_hud itself shows no notification.

Stress gain reads `exports.kora_core:getPlayerData()`; without it nothing is gained.
