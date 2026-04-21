# Brainrot Battlegrounds (Roblox Port)

TFT-style auto-battler where players assemble squads of meme-character
"brainrots" and watch them fight escalating enemy waves across 10 rounds.
Win crates → pull skins (common → mythic) → skins give real stat bonuses.

This is a Rojo-synced Roblox port of a React + Three.js prototype.
Server-authoritative combat, client-side visualization only.

## Project layout

```
src/
├── server/
│   ├── BootstrapInstances.server.luau   -- rebuilds Remotes, arena tiles, unit templates on first boot
│   └── GameServer/
│       ├── Main.server.luau             -- boot, dep injection, RemoteEvent wiring
│       ├── GameManager.luau             -- per-player state + lifecycle
│       ├── CombatEngine.luau            -- tick-based auto-battle resolver
│       ├── AbilityService.luau          -- 10 ability handlers
│       ├── ShopService.luau             -- roll/buy/sell/reroll/combine/level-up
│       ├── UnitSpawner.luau             -- spawns unit Models on the arena grid
│       ├── CrateService.luau            -- (phase 8) crate opening
│       └── DataService.luau             -- (phase 10) DataStore wrapper
├── shared/
│   ├── Constants.luau                   -- game tunables
│   ├── UnitDefinitions.luau             -- 10 brainrots
│   ├── TraitDefinitions.luau            -- 7 traits
│   ├── RarityDefinitions.luau           -- common -> mythic
│   ├── EnemyRounds.luau                 -- 10 waves
│   ├── LevelXP.luau, ShopOdds.luau      -- economy tables
│   └── GameState.luau                   -- shared type exports
└── client/
    ├── ClientMain.client.luau           -- boot, subscribes to remotes
    ├── UIController.luau                -- state-driven UI (in progress)
    ├── CombatRenderer.luau              -- replays CombatEvent stream as visuals
    └── Input.luau                       -- tile/shop clicks (in progress)
```

## Running locally

Requires [Rojo](https://rojo.space/) 7.x.

```bash
rojo serve default.project.json
```

In Studio, install the Rojo plugin and connect. First server boot will run
`BootstrapInstances.server.luau` which creates the RemoteEvents, arena tile
grid, and 10 placeholder unit models.

## Phase status

| Phase | Status | Notes |
|-------|--------|-------|
| 1 — Scaffolding | ✅ | 8 shared modules, 10 remotes, stub services |
| 2 — Unit templates | ✅ | 10 themed primitive models in UnitTemplates |
| 3 — Arena + spawner | ✅ | 6×6 tile grid, rarity outlines, star badges |
| 4 — Combat engine | ✅ | Tick-based sim, 10 abilities, trait effects |
| 5 — Combat visualizer | ✅ | Tween moves, damage floaters, projectiles, AoE rings |
| 6 — Shop loop | ✅ | RollShop, buy/sell/combine, economy, round flow |
| 7 — UI | ⏳ | TopHud + Shop + Bench + TraitPanel |
| 8 — Crates | ⏳ | Open animation, rarity reveal, collection upgrade |
| 9 — Lobby hub | ⏳ | Pedestals + portal |
| 10 — Persistence | ⏳ | DataStore session-lock wrapper |
| 11 — Polish | ⏳ | SFX, music, camera, particles, tutorial |

## Conventions

- `--!strict` where practical
- Server-authoritative — client renders what server tells it
- `PascalCase` Instance names + ModuleScripts, `camelCase` variables, `UPPER_SNAKE_CASE` constants
- Services use DI via `Init(deps)`; no reaching into globals
- RemoteFunctions only when synchronous return is genuinely needed

## Tricky bits

- Unit models animate via `Model:PivotTo` (not Humanoid physics) so combat doesn't knock them around
- `ActorId` attribute is the contract between server (`GameManager.runCombat`) and client (`CombatRenderer.scanActors`)
- `CombatEngine` assigns IDs in player-then-enemy order; `runCombat` spawns visuals in the same order to keep IDs aligned
- Dead units keep their tile occupied until the next tick (per spec "removed from logic the tick after death")
