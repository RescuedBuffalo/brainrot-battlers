--!strict
-- Per-player state owner. Drives the round lifecycle, runs combat, applies
-- post-combat economy, schedules crates, and broadcasts state to clients.
--
-- Lifecycle: lobby -> shop -> combat -> postcombat -> shop -> ... until
-- victory (round > TOTAL_ROUNDS) or defeat (hp <= 0).
--
-- Remote handlers are dispatched via Main.lua; this module exposes
-- Handle* functions that the RemoteEvent wiring calls directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameManager = {}

local Constants
local UnitDefinitions
local EnemyRounds
local ShopService
local CombatEngine
local CrateService
local DataService
local UnitSpawner
local Remotes

type Phase = "lobby" | "shop" | "combat" | "postcombat" | "victory" | "defeat"

type PlayerState = {
    userId: number,
    phase: Phase,
    round: number,
    gold: number,
    hp: number,
    level: number,
    xp: number,
    bench: { any },
    board: { any },
    shop: { any },
    streak: number,
    streakType: string,
    lastResult: any?,
    pendingCrates: { string },
    collection: { [string]: string },
    bestRound: number,
    totalWins: number,
}

local states: { [number]: PlayerState } = {}

-- ---------- state helpers ---------- --

local function newState(userId: number): PlayerState
    local profile = DataService.Load(userId)
    local state: PlayerState = {
        userId = userId,
        phase = "shop",
        round = 1,
        gold = Constants.STARTING_GOLD,
        hp = Constants.STARTING_HP,
        level = Constants.STARTING_LEVEL,
        xp = 0,
        bench = {},
        board = {},
        shop = ShopService.RollShop(Constants.STARTING_LEVEL),
        streak = 0,
        streakType = "none",
        lastResult = nil,
        pendingCrates = {},
        collection = profile.collection,
        bestRound = profile.bestRound,
        totalWins = profile.totalWins,
    }
    return state
end

local function snapshotForClient(state: PlayerState)
    -- Return a plain-table copy safe to replicate. Include everything the UI
    -- renders; omit anything server-only (none currently, but keeps the
    -- contract explicit).
    return {
        phase = state.phase,
        round = state.round,
        gold = state.gold,
        hp = state.hp,
        level = state.level,
        xp = state.xp,
        xpToNext = Constants.MAX_LEVEL > state.level and require(ReplicatedStorage.Shared.LevelXP)[state.level + 1] or 0,
        bench = state.bench,
        board = state.board,
        shop = state.shop,
        streak = state.streak,
        streakType = state.streakType,
        lastResult = state.lastResult,
        pendingCrates = state.pendingCrates,
        collection = state.collection,
        bestRound = state.bestRound,
        totalWins = state.totalWins,
    }
end

local function broadcast(userId: number)
    local state = states[userId]
    if not state then return end
    local player = Players:GetPlayerByUserId(userId)
    if not player then return end
    Remotes.StateUpdate:FireClient(player, snapshotForClient(state))
end

-- ---------- economy ---------- --

local function computeStreakBonus(streak: number): number
    if streak >= 5 then return 3 end
    if streak >= 3 then return 2 end
    if streak >= 2 then return 1 end
    return 0
end

local function applyPostCombat(state: PlayerState, result: any)
    local won = result.outcome == "win"
    local newStreakType = won and "win" or "loss"
    if state.streakType == newStreakType then
        state.streak += 1
    else
        state.streakType = newStreakType
        state.streak = 1
    end

    -- Damage on loss/timeout
    if not won then
        local damage = 3 + state.round
        for _, s in ipairs(result.survivors or {}) do
            damage += (s.cost or 0) * (s.star or 1)
        end
        state.hp = math.max(0, state.hp - damage)
    end

    -- Income (next-round starter). Spec: 5 + interest + streak + stolen.
    local interest = math.min(Constants.MAX_INTEREST, math.floor(state.gold / 10))
    local streakBonus = computeStreakBonus(state.streak)
    local goldStolen = result.goldStolen or 0
    state.gold += Constants.BASE_INCOME + interest + streakBonus + goldStolen

    state.lastResult = {
        outcome = result.outcome,
        ticks = result.ticks,
        damage = won and 0 or (3 + state.round + #(result.survivors or {})),
        incomeBreakdown = {
            base = Constants.BASE_INCOME,
            interest = interest,
            streak = streakBonus,
            stolen = goldStolen,
        },
    }

    -- Crate drop rules from spec
    local crates = {}
    if won then
        table.insert(crates, "common")
        if state.round == 3 or state.round == 6 or state.round == 9 then
            table.insert(crates, "rare")
        end
        if state.round == 5 then
            table.insert(crates, "epic")
        end
        if state.round == 10 then
            table.insert(crates, "legendary")
        end
    else
        if state.round % 2 == 0 then
            table.insert(crates, "common")
        end
    end
    for _, c in ipairs(crates) do
        table.insert(state.pendingCrates, c)
    end

    if won then
        state.totalWins += 1
        if state.round > state.bestRound then
            state.bestRound = state.round
        end
    end
 end

-- ---------- combat orchestration ---------- --

local function normalizeEnemyBoard(roundIndex: number)
    local round = EnemyRounds[roundIndex]
    local out = {}
    for _, e in ipairs(round.units) do
        table.insert(out, { unitId = e[1], star = e[2], rarity = e[3], x = e[4], y = e[5] })
    end
    return out, round.name
end

-- Shop-phase board preview. Clears the arena and respawns only the player's
-- current board (no enemies, no ActorIds). Called from handlers that mutate
-- the board so the world matches state.board.
local function syncShopVisuals(state: PlayerState)
    UnitSpawner.ClearAll()
    for _, u in ipairs(state.board) do
        UnitSpawner.Spawn(u.unitId, u.star, u.rarity, u.x, u.y, "player")
    end
end

local function spawnCombatVisuals(state: PlayerState, enemyBoard)
    UnitSpawner.ClearAll()
    local nextId = 1
    for _, u in ipairs(state.board) do
        local m = UnitSpawner.Spawn(u.unitId, u.star, u.rarity, u.x, u.y, "player")
        if m then m:SetAttribute("ActorId", nextId) end
        nextId += 1
    end
    for _, u in ipairs(enemyBoard) do
        local m = UnitSpawner.Spawn(u.unitId, u.star, u.rarity, u.x, u.y, "enemy")
        if m then m:SetAttribute("ActorId", nextId) end
        nextId += 1
    end
end

local function runCombat(state: PlayerState)
    if state.phase ~= "shop" then return end
    if #state.board == 0 then return end  -- must have at least 1 unit

    state.phase = "combat"
    local enemyBoard, roundName = normalizeEnemyBoard(state.round)

    spawnCombatVisuals(state, enemyBoard)
    task.wait(0.3)  -- let instance replication settle

    local result = CombatEngine.Resolve(state.board, enemyBoard, state.round)

    local player = Players:GetPlayerByUserId(state.userId)
    if player then
        Remotes.CombatEvent:FireClient(player, {
            events = result.events,
            result = {
                outcome = result.outcome,
                ticks = result.ticks,
                goldStolen = result.goldStolen,
                roundName = roundName,
            },
        })
        broadcast(state.userId)  -- phase=combat for UI lock-out
    end

    -- Wait for combat playback, then resolve postcombat
    local playbackSec = result.ticks * Constants.TICK_RATE + 1.2
    task.wait(playbackSec)

    applyPostCombat(state, result)

    if state.hp <= 0 then
        state.phase = "defeat"
    elseif state.round >= Constants.TOTAL_ROUNDS and result.outcome == "win" then
        state.phase = "victory"
    else
        state.phase = "postcombat"
    end
    broadcast(state.userId)
end

-- ---------- handlers ---------- --

function GameManager.HandleBuyUnit(player: Player, slotIdx: number)
    local state = states[player.UserId]
    if not state or state.phase ~= "shop" then return end
    if type(slotIdx) ~= "number" then return end
    if ShopService.Buy(state, slotIdx) then
        -- A cascading 3-combine can consume a board unit; resync just in case.
        syncShopVisuals(state)
        broadcast(player.UserId)
    end
end

function GameManager.HandleSellUnit(player: Player, source: string, idx: number)
    local state = states[player.UserId]
    if not state or state.phase ~= "shop" then return end
    if type(source) ~= "string" or type(idx) ~= "number" then return end
    if ShopService.Sell(state, source, idx) then
        if source == "board" then syncShopVisuals(state) end
        broadcast(player.UserId)
    end
end

function GameManager.HandlePlaceUnit(player: Player, payload: any)
    local state = states[player.UserId]
    if not state or state.phase ~= "shop" then return end
    if type(payload) ~= "table" then return end
    local fromLoc = payload.fromLoc
    local fromIdx = payload.fromIdx
    local toLoc = payload.toLoc
    local toIdx = payload.toIdx
    local x = payload.x
    local y = payload.y
    if type(fromLoc) ~= "string" or type(fromIdx) ~= "number" then return end
    if type(toLoc) ~= "string" then return end
    if ShopService.PlaceUnit(state, fromLoc, fromIdx, toLoc, toIdx or 0, x, y) then
        syncShopVisuals(state)
        broadcast(player.UserId)
    end
end

function GameManager.HandleRerollShop(player: Player)
    local state = states[player.UserId]
    if not state or state.phase ~= "shop" then return end
    if ShopService.Reroll(state) then
        broadcast(player.UserId)
    end
end

function GameManager.HandleBuyXP(player: Player)
    local state = states[player.UserId]
    if not state or state.phase ~= "shop" then return end
    if ShopService.BuyXP(state) then
        broadcast(player.UserId)
    end
end

function GameManager.HandleStartCombat(player: Player)
    local state = states[player.UserId]
    if not state or state.phase ~= "shop" then return end
    task.spawn(runCombat, state)
end

function GameManager.HandleNextRound(player: Player)
    local state = states[player.UserId]
    if not state or state.phase ~= "postcombat" then return end
    state.round += 1
    state.phase = "shop"
    state.shop = ShopService.RollShop(state.level)
    state.lastResult = nil
    UnitSpawner.ClearAll()
    -- Respawn player board visuals for the shop phase so placements are visible
    for _, u in ipairs(state.board) do
        local m = UnitSpawner.Spawn(u.unitId, u.star, u.rarity, u.x, u.y, "player")
        -- No ActorId in shop phase (nothing to animate)
    end
    broadcast(player.UserId)
end

function GameManager.HandleOpenCrate(player: Player)
    local state = states[player.UserId]
    if not state then return end
    if #state.pendingCrates == 0 then return end
    local tier = table.remove(state.pendingCrates, 1)
    if CrateService and CrateService.Open then
        local drop = CrateService.Open(player.UserId, tier)
        if drop then
            state.collection = DataService.Load(player.UserId).collection
            if drop.goldRefund and drop.goldRefund > 0 then
                state.gold += drop.goldRefund
            end
        end
    end
    broadcast(player.UserId)
end

-- ---------- lifecycle ---------- --

function GameManager.Init(deps)
    local shared = deps.Shared
    Constants = require(shared:WaitForChild("Constants"))
    UnitDefinitions = require(shared:WaitForChild("UnitDefinitions"))
    EnemyRounds = require(shared:WaitForChild("EnemyRounds"))
    ShopService = deps.ShopService
    CombatEngine = deps.CombatEngine
    CrateService = deps.CrateService
    DataService = deps.DataService
    UnitSpawner = deps.UnitSpawner
    Remotes = deps.Remotes
end

function GameManager.GetState(userId: number)
    return states[userId]
end

function GameManager.OnPlayerAdded(player: Player)
    local state = newState(player.UserId)
    states[player.UserId] = state
    broadcast(player.UserId)
end

function GameManager.OnPlayerRemoving(player: Player)
    DataService.Save(player.UserId)
    DataService.Release(player.UserId)
    states[player.UserId] = nil
end

return GameManager
