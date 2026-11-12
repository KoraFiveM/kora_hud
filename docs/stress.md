---
title: Stress
sidebar_position: 10
---

# Stress

`client/stress.lua` raises the player's stress client-side, restoring the qb-hud behaviour. It runs only when `Config.stress.enabled` is not false. Config is read on every tick, so edits apply immediately.

## Rules

- **Speeding** (`Config.stress.speed`): while in a vehicle, every `interval` ms (minimum 500, default 10000) the speed is compared with `threshold` (default 180) in `unit` (`'kmh'` or `'mph'`). At or above it, stress rises by a random whole number between `gainMin` and `gainMax` (1 to 3). With `driverOnly` (default true) only the driver gains stress. The worker exists only while the player is in a vehicle.
- **Shooting** (`Config.stress.shooting`): while a firearm or throwable is held (pistol, SMG, rifle, MG, shotgun, sniper, heavy, thrown, stun gun weapon groups) and the player is not dead, shots are sampled. Each shot check succeeds with `chance` percent (default 50), then adds `gainMin` to `gainMax`, and waits at least `cooldown` ms (default 3000, minimum 100) before the next. Hashes in `whitelistedWeapons` never cause stress.
- **Job whitelist**: players whose job name is in `whitelistedJobs` (default `police`) never gain stress.
- Stress is capped at 100.

## Persistence

The new value is sent with `TriggerServerEvent('QBCore:Server:SetMetaData', 'stress', value)`, which is handled by `kora_core`'s compatibility layer, not by this resource. The `kora_core` setting `Config.compat.clientMetadataKeys.stress` must allow it (documented in code as enabled by default). The HUD then receives the new value through the normal metadata update. Because the client computes and sends the value, stress is client-authoritative.

If `Config.stress.notify` is not false, `kora_hud:client:stressGained` is raised locally with the new value, at most every 10 seconds, for notification resources. kora_hud itself shows no notification.

Stress gain reads `exports.kora_core:getPlayerData()`; without it nothing is gained.
