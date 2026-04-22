# Brainrot Battlegrounds (Roblox Port)

TFT-style auto-battler where players assemble squads of meme-character
"brainrots" and watch them fight escalating enemy waves across 10 rounds.
Win crates → pull skins (common → mythic) → skins give real stat bonuses.

This is a Rojo-synced Roblox port of a React + Three.js prototype.
Server-authoritative combat, client-side visualization only.

## Status

MVP complete — all 11 phases shipped. Single-player PvE campaign runs
end-to-end: lobby pedestals → shop → tick-based combat → post-combat economy
→ crate reveals → collection upgrades persist across sessions via DataStore.

## Project layout

```
src/
├── server/
│   ├── BootstrapInstances.server.luau   -- recreates Remotes, arena tiles,
│   │                                       unit templates, lobby geometry
│   │                                       on first boot (idempotent)
│   └── GameServer/
│       ├── Main.server.luau             -- boot, DI, RemoteEvent wiring,
│       │                                   autosave + BindToClose
│       ├── GameManager.luau             -- per-player state, lifecycle,
│       │                                   combat orchestration, economy
│       ├── CombatEngine.luau            -- tick-based auto-battle resolver
│       ├── AbilityService.luau          -- 10 ability handlers
│       ├── ShopService.luau             -- roll/buy/sell/reroll/combine/
│       │                                   level-up, cascading 3-merge
│       ├── UnitSpawner.luau             -- places unit Models on the grid
│       │                                   with rarity outlines + stars
│       ├── CrateService.luau            -- weighted rarity roll, upgrade
│       │                                   or +3 gold consolation
│       ├── LobbyService.luau            -- populates pedestals with the
│       │                                   player's collection display
│       └── DataService.luau             -- DataStoreService wrapper with
│                                           session locks + fallback
├── shared/
│   ├── Constants.luau                   -- game tunables
│   ├── UnitDefinitions.luau             -- 10 brainrots
│   ├── TraitDefinitions.luau            -- 7 traits
│   ├── RarityDefinitions.luau           -- common → mythic
│   ├── EnemyRounds.luau                 -- 10 waves
│   ├── LevelXP.luau, ShopOdds.luau      -- economy tables
│   └── GameState.luau                   -- shared type exports
├── client/
│   ├── ClientMain.client.luau           -- boot, subscribes to remotes,
│   │                                       routes to controllers
│   ├── UIController.luau                -- MainUI ScreenGui (TopHud, Shop,
│   │                                       Bench, TraitPanel, Collection
│   │                                       + CrateReveal modals)
│   ├── CombatRenderer.luau              -- replays the server's CombatEvent
│   │                                       stream at TICK_RATE
│   ├── Input.luau                       -- tile ClickDetectors → UIController
│   ├── SoundController.luau             -- named SFX registry + music
│   ├── CameraController.luau            -- phase-driven scripted camera
│   └── Tutorial.luau                    -- first-run 3-step overlay
└── tools/
    └── generate_portraits.py            -- (ops) offline portrait asset helper
```

## Running locally

Requires [Aftman](https://github.com/LPGhatguy/aftman) (toolchain manager),
the [Rojo Studio plugin](https://rojo.space/docs/v7/getting-started/installation/#install-the-roblox-studio-plugin),
and **Game Settings → Security → "Enable Studio Access to API Services"**
turned on (for DataStore persistence during local testing).

```bash
# one-time: installs the pinned Rojo version from aftman.toml
aftman install

# every time you want to sync
rojo serve
```

In Studio: open a baseplate, install the Rojo plugin, click Connect (default
port 34872). The first server boot runs `BootstrapInstances.server.luau` which
idempotently builds the RemoteEvents, arena tile grid, 10 unit templates, and
lobby platform — a fresh clone comes up fully playable.

### Without Aftman

Install Rojo 7.x directly (`cargo install rojo`, prebuilt binary, etc.) and
run `rojo serve` in the repo root. If Aftman intercepts, either add Rojo to
your user-global `~/.aftman/aftman.toml` or just `aftman install` here.

## Phase status

| Phase | Status | Notes |
|-------|--------|-------|
| 1 — Scaffolding | ✅ | 8 shared modules, 10 remotes + 1 RF, stub services |
| 2 — Unit templates | ✅ | 10 themed Parts+Humanoid Models in UnitTemplates |
| 3 — Arena + spawner | ✅ | 6×6 tile grid, rarity Highlights, star badges, particle auras for legendary+/mythic |
| 4 — Combat engine | ✅ | Tick-based sim, 10 abilities, 7 traits with tiered effects, Chebyshev pathing |
| 5 — Combat visualizer | ✅ | Tween moves, damage floaters, crit colors, projectiles, AoE rings, death shrinks |
| 6 — Shop loop | ✅ | Roll/buy/sell/reroll/level-up, cascading 3-combine, economy (interest/streak/gold-stolen), round flow |
| 7 — UI | ✅ | TopHud + Shop + Bench + TraitPanel + post-combat/end-game overlays, tap-to-select placement |
| 8 — Crates + Collection | ✅ | Shake/burst/reveal animation, rarity-colored outlines, grid modal |
| 9 — Lobby hub | ✅ | 10 pedestals in an arc with live collection display, glowing portal, SpawnLocation |
| 10 — Persistence | ✅ | DataStore session-lock wrapper, retry w/ backoff, autosave + BindToClose, graceful fallback |
| 11 — Polish | ✅ | SFX registry, phase-driven scripted camera, first-run tutorial persisted to profile |

## Conventions

- `--!strict` where practical
- Server-authoritative — client renders what server tells it, never mutates
  gameplay state locally
- `PascalCase` Instance names + ModuleScripts, `camelCase` variables,
  `UPPER_SNAKE_CASE` constants
- Services use DI via `Init(deps)`; no reaching into globals
- RemoteFunctions only when synchronous return is genuinely needed
  (currently only `GetPlayerState` for client bootstrap)
- Every RemoteEvent handler validates its arguments on the server; clients
  are hostile by default

## Tricky bits

- Unit models animate via `Model:PivotTo` (not Humanoid physics) so combat
  doesn't knock them around. Humanoids are kept for `Head` requirements +
  future HP bars.
- `ActorId` attribute is the contract between server (`GameManager.runCombat`
  spawns with `m:SetAttribute("ActorId", n)`) and client
  (`CombatRenderer.scanActors` reads them to match events → Models).
- `CombatEngine` assigns actor IDs in player-then-enemy order; `runCombat`
  spawns visuals in the same order to keep IDs aligned across server and
  client.
- Dead units keep their tile occupied until the *next* tick (per spec:
  "removed from logic the tick after death") — the tile map purge runs at
  tick-start, not on death.
- `DataService` probes the DataStore API at `Init` time. If the probe fails
  (Studio without API access, or a DataStore outage) it flips to a log-only
  in-memory fallback so gameplay never blocks on storage.
- `CameraController` reapplies its preset on `CharacterAdded` and
  `Workspace.CurrentCamera` change because the default Humanoid controller
  resets `CameraType = Custom` on every respawn.
- `SoundController` pitch-shifts a handful of verified `rbxasset://` paths
  to cover 12 logical SFX slots — swap in Creator Store asset IDs in the
  `REGISTRY` table to upgrade without touching any call sites.

## Contributing / Deploying

- Branches are named `phase-N-*` for feature chains and `docs/*` or `fix/*`
  for smaller changes. Open a PR against `main` per branch.
- No CI configured yet; `rojo serve` + in-Studio Play is the test loop.
- Data schema is versioned (`profile.version`) — when changes require
  migration, bump the number and add a step in `DataService.migrate()`.
