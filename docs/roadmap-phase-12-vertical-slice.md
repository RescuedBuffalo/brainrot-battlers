# Phase 12 — Vertical Slice: Moment Layer + Run Map

**Goal in one line:** Prove the "Slay the Spire-shaped run + cinematic ability moments" direction with a playable vertical slice before any content-complete pass.

> See `README.md` for project context, layout, and conventions. This doc only describes the new work for Phase 12. All conventions in the README still apply (server-authoritative, DI via `Init(deps)`, `--!strict`, validate all remote args, etc.).

## Why this phase

The MVP loop (10 rounds, fixed shop, one act) is mechanically sound but flat over multiple sessions. Two known-good directions to test:

1. **Run shape** — replace the fixed round 1→10 march with a Slay the Spire-style branching node map. Adds run-to-run variance, build identity, and choice depth without abandoning the existing combat engine.
2. **Moment Layer** — a reusable feedback-stacking system that any ability can call to produce 6–8 simultaneous layers of feedback (camera punch, time-dilated tweens, vignette, hit-stop, particle burst, big numbers, VO bark, color flash). Right now abilities have ~3 isolated feedback layers; goal is "OH GOD" moments on legendary casts.

**Vertical slice, not content-complete.** Build both systems end-to-end, but apply them only to a minimum surface area: one fully-moment-ified ability and a 5–8 node map with ~3 event cards and ~3 forge cards. Then play 3–5 runs and decide whether to invest further.

This is explicitly designed to be ~1–2 weekends of work, not a quarter.

---

## Workstream A — Moment Layer

### Deliverable

A reusable client service that any ability handler can call to fire a stacked, configurable set of visual/audio feedback layers around a moment in time. Apply it fully to **one ability** as the showcase.

### Files

- **NEW:** `src/client/MomentService.luau` — the orchestrator. Public API:
  ```lua
  MomentService.Init(deps)  -- deps: SoundController, CameraController, CombatRenderer
  MomentService.play(name: string, context: MomentContext)
  -- context fields: sourceActorId, targetActorId, position (Vector3), trait (string?)
  ```
- **NEW:** `src/client/MomentDefinitions.luau` — table keyed by moment name (matches ability ID), each entry declares which layers fire and at what intensity. Example:
  ```lua
  ohio_reality_collapse = {
      cameraPunch = { intensity = 1.0, durationMs = 220 },
      timeDilation = { factor = 0.35, durationMs = 280 },
      vignette = { color = TraitColors.ohio, alpha = 0.55, durationMs = 320 },
      hitStop = { targetMs = 90 },
      particleBurst = { template = "OhioCollapse", count = 60 },
      bigNumber = { scale = 1.6, color = Color3.fromRGB(160, 60, 220) },
      screenShake = { intensity = 0.8, durationMs = 200 },
      vo = { soundId = "VO_Ohio_RealityCollapse", volume = 1.0 },
  }
  ```
- **MODIFY:** `src/client/CombatRenderer.luau` — when an ability event arrives in the combat event stream, call `MomentService.play(abilityId, context)` *in addition to* the existing per-ability visualization. Existing rendering (projectiles, damage floaters) stays — moments are additive polish, not a replacement.
- **MODIFY:** `src/client/SoundController.luau` — add a `VO_REGISTRY` table for voice barks per ability/unit. Same pattern as existing `REGISTRY` (asset IDs swappable later).
- **MODIFY:** `src/client/CameraController.luau` — expose `punch(direction: Vector3, intensity: number, durationMs: number)` and `shake(intensity: number, durationMs: number)`. Both must restore the active preset on completion (the controller already reapplies preset on respawn — same pattern).
- **MODIFY:** `src/client/ClientMain.client.luau` — wire MomentService into the boot graph with its deps.

### Layer implementation notes

- **Time dilation is a visual trick only.** Server combat tick rate is fixed and authoritative. CombatRenderer should elongate its in-flight tweens for the moment's duration and then resume normal replay timing. Do NOT touch tick rate or server state. If the server emits 3 events during a 280ms dilation, render them all proportionally slower then snap back.
- **Hit-stop** = freeze the target unit's `Model:PivotTo` interpolation for `targetMs`, then resume.
- **Vignette** = a full-screen `ScreenGui` frame with a radial gradient, alpha-tweened in then out. Add it once at boot, reuse.
- **BigNumber** = use the existing damage floater pipeline with a scale + color override pulled from the moment definition.
- **ParticleBurst** = `ParticleEmitter` parented to a temporary attachment at `context.position`, `Emit(count)`, then `Destroy()` after lifetime.
- **Camera punch** = brief offset CFrame applied on top of the current preset, eased back. Camera shake = randomized offsets at `intensity` magnitude over duration.

### Showcase ability

**Pick `capuchino_shadow_leap`.** Reasoning: 4-cost so it triggers reliably in mid-late runs (testable), single-target burst is easy to choreograph, "leap to priciest enemy + 320% AD crit" naturally maps to a slow-mo / vignette / VO moment without competing with multi-target chaos. Build and tune the full Moment definition for this one ability. Other abilities can stay on existing visualization for v1.

### Acceptance criteria

- `MomentService.play("capuchino_shadow_leap", ctx)` produces all 8 layers stacked and visible in a single playthrough.
- Camera, vignette, and hit-stop fully restore after the moment ends — no residual state if the unit dies mid-moment.
- Other abilities still render normally with no regressions.
- Moment plays correctly when the casting unit is on the player's side AND the enemy's side (no assumptions about ownership).

---

## Workstream B — Run Map (STS-shape)

### Deliverable

Replace the fixed `round 1 → round 10` march with a branching node map. Player picks the next node from 2–3 visible options after each completed node. v1 ships with 5 node types and a curated map shape.

### Map shape for v1

- Total nodes per run: **8–12** (was 10 rounds; we're trading some combats for non-combat texture).
- Combat encounter count: **5–7** (vs. 10 today). Re-use the existing `EnemyRounds.luau` enemy comps but allow them to appear out of order — picked by the map generator from a difficulty-tagged pool.
- Always-fixed first node: **Combat** (tutorial/onboarding stays predictable).
- Always-fixed last node: **Boss** (the round-10 enemy, now an event you draft toward).
- Branching factor: 2–3 visible next nodes per choice. Map is a directed acyclic graph generated at run-start, server-authoritative.

### Node types for v1

1. **Combat** — uses existing `runCombat` flow.
2. **Elite Combat** — same as Combat but pulls from a harder enemy pool, guaranteed crate on win.
3. **Shop** — opens current Shop UI as a standalone interaction (not bundled with a fight). Free reroll + shop odds shifted +1 rarity tier this visit. No XP/HP tick.
4. **Event** — text-choice event from a card pool. Pick 1 of 2 framed outcomes. Pure flavor + small mechanical impact.
5. **Forge** — pick 1 of 3 run-modifying cards that persist for the rest of the run.
6. **Boss** — final node. Always last.

### Files

- **NEW:** `src/shared/RunMap.luau` — types + map generator. Pure function: `generate(seed: number, length: number) -> RunMap`. Map is a list of nodes with `id`, `type`, `nextNodeIds`, `payload` (e.g. for Combat: which enemy comp).
- **NEW:** `src/shared/CardDefinitions.luau` — keyed table of all event + forge cards. v1 seed below.
- **NEW:** `src/server/GameServer/RunMapService.luau` — owns the active map per player, validates that the player's chosen `nextNodeId` is actually adjacent to current node, advances state.
- **NEW:** `src/server/GameServer/CardService.luau` — applies card effects to `GameState`. Cards declare effect type + magnitude in their definition; the service has a small dispatch table.
- **NEW:** `src/client/RunMapController.luau` — renders the map UI, highlights current node + valid next nodes, fires `SelectNextNode` remote on click.
- **NEW:** `src/client/CardDraftController.luau` — renders 3-card pick modal for Forge nodes and 2-choice modal for Events.
- **MODIFY:** `src/server/GameServer/GameManager.luau` — replace fixed-round loop with map-driven flow. After each node completes, push state to client and wait for `SelectNextNode`. Combat nodes still call existing `runCombat`. Economy hooks (gold, interest, streak) only tick on Combat/Elite nodes.
- **MODIFY:** `src/server/BootstrapInstances.server.luau` — add new RemoteEvents: `RunMapUpdate` (server→client, full map state), `SelectNextNode` (client→server, with `nodeId`), `CardChoice` (client→server, with `cardId` and optional `targetUnitInstanceId`).
- **MODIFY:** `src/client/UIController.luau` — add a "View Map" toggle in TopHud.
- **MODIFY:** `src/shared/GameState.luau` — extend the player state shape to include `runMap`, `currentNodeId`, `activeCards` (forge effects).

### v1 card pool (seed content)

**Event cards (3, presented at Event nodes — show 2, pick 1):**

1. **Tung Tung's Nap** — Pick one unit on your bench or board: +200 max HP for the rest of the run. Cost: lose 3 gold.
2. **Espresso Spill** — All Italian units gain +20% attack speed *for the next combat only*. Cost: -1 bench slot for the next combat.
3. **Skibidi Toilet Portal** — Refresh shop for free at the next Shop node, AND your next combat begins with +1 enemy unit.

**Forge cards (3, presented at Forge nodes — show 3, pick 1, persists run-long):**

1. **Ohio Energy** — Ohio trait thresholds reduced by 1 (e.g. 2 Ohio = bonus instead of needing 3).
2. **Sigma Grindset** — All Sigma units gain +5% AD per Combat node won this run (compounds, capped at +50%).
3. **Tralalero Surge** — When any Tralalero-trait unit casts, all allied Italian units gain 20 mana.

This is intentionally tiny — enough variety to feel different across 3 runs, small enough to fully tune. Expansion comes after playtesting.

### Acceptance criteria

- Starting a new run generates a valid 8–12 node map with the correct first/last node fixtures and 2–3 branching factor.
- Player can complete a full run via the map: at least one of each non-Combat node type appears in a typical generated map.
- Forge card selections persist for the rest of the run and visibly affect combat (e.g. Ohio Energy lets a 2-unit Ohio comp activate the trait bonus).
- Event card outcomes apply correctly and clear when scope expires (per-combat effects).
- Map state survives a leave/rejoin within the same session via the existing DataService autosave path. (Schema bump in `profile.version` + a `migrate()` step.)
- Server validates every `SelectNextNode` against the current node's adjacency list — silently rejects invalid picks.

---

## Out of scope for Phase 12

These are real future work but explicitly NOT this phase. Do not expand scope into them.

- New brainrot units beyond the existing 10
- New traits beyond the existing 7
- Custom modeled unit replacements (still using current Part+Humanoid templates)
- Audio/VO asset acquisition — use placeholder asset IDs in the new `VO_REGISTRY`; swap later
- PvP / multiplayer / matchmaking / shared shop
- Battle pass, daily quests, login rewards, ranked
- Ability rebalancing — keep all existing ability numbers as-is
- Economy rebalancing beyond what map shape forces (e.g. adjusting gold-per-Combat to compensate for fewer combats per run)
- Visual upgrades to other 9 abilities — only `capuchino_shadow_leap` gets the full Moment treatment in v1
- New arenas / stage variety
- New crate art

If something on this list feels load-bearing during implementation, surface it as a follow-up rather than expanding the slice.

---

## Suggested order of attack

Sequencing matters because the goal is a *playable* slice as fast as possible. Recommend the order below, with checkpoints where the build should be runnable end-to-end.

1. **Workstream B scaffolding first.** Build `RunMap.luau`, `RunMapService.luau`, `RunMapController.luau`, and rewire `GameManager` to map-driven flow with ONLY Combat + Boss nodes. Verify a 3-combat map plays end-to-end with the existing combat engine untouched. **Checkpoint: runnable.**
2. **Add Shop and Elite node types.** Both reuse existing systems — Shop is the existing UI standalone, Elite is Combat with a different enemy pool + guaranteed crate. **Checkpoint: runnable, 4 node types live.**
3. **Add CardService + Event/Forge nodes + the 6 v1 cards.** This is the biggest unknown — leave time to iterate on how cards apply. **Checkpoint: runnable, full map shape playable.**
4. **Workstream A — MomentService scaffolding.** Build the service with stub layer implementations (just print statements per layer). Wire it into CombatRenderer. **Checkpoint: ability events trigger MomentService calls but nothing visible yet.**
5. **Implement layers one at a time.** Order: bigNumber → particleBurst → cameraPunch → vignette → hitStop → timeDilation → screenShake → vo. Each layer should be independently testable. **Checkpoint: runnable, Moment fires on Capuchino with all layers.**
6. **Tune the Capuchino moment.** This is iteration time, not engineering time. Adjust intensities, durations, color, sound. **Checkpoint: it feels good.**
7. **Play 3–5 full runs.** Document what felt off, what felt great. Phase 12 ends here. Don't expand.

A reasonable solo timeline: steps 1–3 in one weekend, steps 4–7 the next.

---

## How we'll know the slice succeeded

After playing 3–5 runs:

- "I want to start another run" is a yes (subjective but the only metric that matters for a passion project).
- The branching map produced visibly different runs (different combat order, different forge picks → different end-game comps).
- The Capuchino moment produces a noticeable "oh damn" reaction even after seeing it 5+ times.
- No regressions — every existing system (shop, crates, lobby, persistence, tutorial) still works.

If yes on all four, Phase 13 is content expansion: Moment-ify the other 9 abilities, grow the card pool to 15–20, add 1–2 new node types (Rest, Shrine, etc.), tune economy to the new run shape.

If no on the run-shape one, the issue is probably card pool size — 6 cards is small, expand before declaring the shape wrong.

If no on the Moment one, tune intensities up before adding more abilities — the layer system is right, the values are wrong.
