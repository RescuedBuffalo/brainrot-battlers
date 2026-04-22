--!strict
-- Per-player state owner. Drives the map-based run flow (Phase 12):
-- lobby -> shop (pre-combat) -> combat -> postcombat -> nodeSelect ->
-- next node (shop / combat / event / forge / boss) -> ... until boss is
-- resolved (victory) or HP hits 0 (defeat).
--
-- Non-combat nodes use their own phase so the client UI can render the
-- right panel (event/forge draft, standalone shop, map selector).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameManager = {}

local Constants
local UnitDefinitions
local EnemyRounds
local CardDefinitions
local ShopService
local CombatEngine
local CrateService
local LobbyService
local DataService
local UnitSpawner
local RunMapService
local CardService
local Remotes

type Phase =
    "lobby" | "shop" | "combat" | "postcombat" | "nodeSelect"
    | "shopNode" | "eventDraft" | "forgeDraft" | "unitTarget"
    | "victory" | "defeat"

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
    tutorialDone: boolean,
    -- Phase 12
    runMap: any?,
    currentNodeId: string?,
    activeCards: { any },
    combatsWon: number,
    pendingDraft: any?,   -- list of card ids currently offered
    pendingTarget: any?,  -- card id awaiting a unit target from the client
}

local states: { [number]: PlayerState } = {}

-- ---------- state helpers ---------- --

local function rollNewRun(state: PlayerState)
    state.runMap = RunMapService.NewMap()
    state.currentNodeId = state.runMap.startNodeId
    state.activeCards = {}
    state.combatsWon = 0
    state.round = 1  -- display number; updated on combat node entry
end

-- Snapshot the run to the profile so a leave/rejoin resumes cleanly.
-- Called after every state transition that mutates the run.
local function persistRun(state: PlayerState)
    if not DataService.SetRunState then return end
    DataService.SetRunState(state.userId, {
        runMap = state.runMap,
        currentNodeId = state.currentNodeId,
        activeCards = state.activeCards,
        combatsWon = state.combatsWon,
        bench = state.bench,
        board = state.board,
        gold = state.gold,
        hp = state.hp,
        level = state.level,
        xp = state.xp,
        streak = state.streak,
        streakType = state.streakType,
        pendingCrates = state.pendingCrates,
    })
end

-- Apply a saved run snapshot onto a fresh state. Only touches fields we
-- actually persisted; leaves phase, shop, etc. to be set by the caller.
local function restoreRun(state: PlayerState, saved: any)
    if not saved then return end
    state.runMap = saved.runMap
    state.currentNodeId = saved.currentNodeId
    state.activeCards = saved.activeCards or {}
    state.combatsWon = saved.combatsWon or 0
    state.bench = saved.bench or {}
    state.board = saved.board or {}
    state.gold = saved.gold or state.gold
    state.hp = saved.hp or state.hp
    state.level = saved.level or state.level
    state.xp = saved.xp or state.xp
    state.streak = saved.streak or 0
    state.streakType = saved.streakType or "none"
    state.pendingCrates = saved.pendingCrates or {}
end

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
        tutorialDone = profile.tutorialDone or false,
        runMap = nil,
        currentNodeId = nil,
        activeCards = {},
        combatsWon = 0,
        pendingDraft = nil,
        pendingTarget = nil,
    }

    -- Restore in-progress run if the profile has one, else roll fresh.
    if profile.runState and profile.runState.runMap and profile.runState.currentNodeId then
        restoreRun(state, profile.runState)
        -- Land on the current node's appropriate phase.
        local node = state.runMap.nodes[state.currentNodeId]
        if node and not node.visited then
            if node.type == "combat" or node.type == "elite" or node.type == "boss" then
                state.phase = "shop"
                state.shop = ShopService.RollShop(state.level)
            elseif node.type == "shop" then
                state.phase = "shopNode"
                state.shop = ShopService.RollShop(state.level)
            elseif node.type == "event" then
                state.phase = "nodeSelect"  -- re-draw card options next time
            elseif node.type == "forge" then
                state.phase = "nodeSelect"
            end
        elseif node and node.visited then
            state.phase = "nodeSelect"
        end
    else
        rollNewRun(state)
    end
    return state
end

local function snapshotForClient(state: PlayerState)
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
        tutorialDone = state.tutorialDone,
        runMap = state.runMap,
        currentNodeId = state.currentNodeId,
        activeCards = state.activeCards,
        combatsWon = state.combatsWon,
        pendingDraft = state.pendingDraft,
        pendingTarget = state.pendingTarget,
        benchCapOverride = state.benchCapOverride,
        currentShopFreeReroll = state.currentShopFreeReroll,
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

local function crateForNode(state: PlayerState, node: any, won: boolean): { string }
    local out = {}
    if not won then
        -- Losing a combat gives a common crate on even rounds (legacy rule
        -- preserved for map-based flow too)
        if state.combatsWon % 2 == 0 then table.insert(out, "common") end
        return out
    end
    if node.type == "boss" then
        table.insert(out, "legendary")
        table.insert(out, "epic")
    elseif node.type == "elite" then
        table.insert(out, node.payload.guaranteedCrate or "rare")
    else
        table.insert(out, "common")
        -- Scale rarity with combatsWon so later-game crates stay exciting
        if state.combatsWon >= 3 and state.combatsWon % 3 == 0 then
            table.insert(out, "rare")
        end
        if state.combatsWon == 5 then
            table.insert(out, "epic")
        end
    end
    return out
end

local function applyPostCombat(state: PlayerState, result: any, node: any)
    local won = result.outcome == "win"
    local newStreakType = won and "win" or "loss"
    if state.streakType == newStreakType then
        state.streak += 1
    else
        state.streakType = newStreakType
        state.streak = 1
    end

    if not won then
        local damage = 3 + (node.payload.enemyRound or 1)
        for _, s in ipairs(result.survivors or {}) do
            damage += (s.cost or 0) * (s.star or 1)
        end
        state.hp = math.max(0, state.hp - damage)
    end

    -- Economy only ticks on Combat/Elite/Boss nodes (spec).
    local interest = math.min(Constants.MAX_INTEREST, math.floor(state.gold / 10))
    local streakBonus = computeStreakBonus(state.streak)
    local goldStolen = result.goldStolen or 0
    state.gold += Constants.BASE_INCOME + interest + streakBonus + goldStolen

    state.lastResult = {
        outcome = result.outcome,
        ticks = result.ticks,
        damage = won and 0 or (3 + (node.payload.enemyRound or 1) + #(result.survivors or {})),
        incomeBreakdown = {
            base = Constants.BASE_INCOME,
            interest = interest,
            streak = streakBonus,
            stolen = goldStolen,
        },
    }

    for _, c in ipairs(crateForNode(state, node, won)) do
        table.insert(state.pendingCrates, c)
    end

    if won then
        state.combatsWon += 1
        state.totalWins += 1
        -- bestRound now tracks combats won (not "round number")
        if state.combatsWon > state.bestRound then
            state.bestRound = state.combatsWon
        end
        if DataService.BumpStats then
            DataService.BumpStats(state.userId, state.bestRound, state.totalWins)
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

-- Apply Skibidi Portal extraEnemies: duplicate the first N enemies at empty
-- enemy tiles. Cheap hack for v1 -- Phase 13 can make this smarter.
local function applyExtraEnemies(enemyBoard, extra: number)
    if extra <= 0 then return enemyBoard end
    local occupied = {}
    for _, u in ipairs(enemyBoard) do occupied[u.x .. "," .. u.y] = true end
    local sample = enemyBoard[1]
    if not sample then return enemyBoard end
    for added = 1, extra do
        for y = 0, 2 do
            for x = 0, 5 do
                if not occupied[x .. "," .. y] then
                    table.insert(enemyBoard, { unitId = sample.unitId, star = sample.star, rarity = sample.rarity, x = x, y = y })
                    occupied[x .. "," .. y] = true
                    break
                end
            end
            if occupied[sample.x .. "," .. sample.y] then break end
        end
    end
    return enemyBoard
end

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
    if #state.board == 0 then return end
    local node = RunMapService.CurrentNode(state)
    if not node then return end

    if not state.tutorialDone then
        state.tutorialDone = true
        if DataService.SetTutorialDone then
            DataService.SetTutorialDone(state.userId)
        end
    end

    -- End of shop visit (pre-combat branch). Skibidi Portal's freeReroll
    -- half expires here even if never used; the +1 enemy half persists via
    -- activeCards until combat actually begins (next-combat scope).
    if state.currentShopFreeReroll then
        CardService.ClearFreeRerollFlag(state)
    end
    state.currentShopFreeReroll = false
    state.currentShopCostShift = 0

    state.phase = "combat"
    local enemyBoard, roundName = normalizeEnemyBoard(node.payload.enemyRound or 1)

    -- Build combat mods from active cards BEFORE spawning visuals.
    local mods = CardService.BuildCombatMods(state)
    if mods.extraEnemies and mods.extraEnemies > 0 then
        enemyBoard = applyExtraEnemies(enemyBoard, mods.extraEnemies)
    end

    spawnCombatVisuals(state, enemyBoard)
    task.wait(0.3)

    local result = CombatEngine.Resolve(state.board, enemyBoard, node.payload.enemyRound or 1, mods)

    local player = Players:GetPlayerByUserId(state.userId)
    if player then
        Remotes.CombatEvent:FireClient(player, {
            events = result.events,
            result = {
                outcome = result.outcome,
                ticks = result.ticks,
                goldStolen = result.goldStolen,
                roundName = roundName,
                nodeType = node.type,
            },
        })
        broadcast(state.userId)
    end

    local playbackSec = result.ticks * Constants.TICK_RATE + 1.2
    task.wait(playbackSec)

    applyPostCombat(state, result, node)

    -- Next-combat-scope cards expire here
    CardService.ExpireNextCombatCards(state)
    -- Espresso Spill's bench penalty is tied to the "next combat" shop
    -- visit we just left; clear the override now that combat has consumed it.
    state.benchCapOverride = nil

    if state.hp <= 0 then
        state.phase = "defeat"
        if DataService.SetRunState then DataService.SetRunState(state.userId, nil) end
    elseif node.type == "boss" and result.outcome == "win" then
        RunMapService.MarkCurrentVisited(state)
        state.phase = "victory"
        if DataService.SetRunState then DataService.SetRunState(state.userId, nil) end
    else
        state.phase = "postcombat"
        persistRun(state)
    end
    broadcast(state.userId)
end

-- ---------- node entry ---------- --

local function enterNode(state: PlayerState, nodeId: string)
    state.currentNodeId = nodeId
    local node = state.runMap.nodes[nodeId]
    if not node then return end
    if node.type == "combat" or node.type == "elite" or node.type == "boss" then
        -- Pre-combat shop phase using current level
        state.round = node.payload.enemyRound or state.round
        state.currentShopCostShift = 0
        state.currentShopFreeReroll = CardService.HasFreeRerollFlag(state)
        -- Espresso Spill: -1 bench slot for the next Combat's pre-combat shop.
        -- Bench slots that get "disabled" are the highest-index ones, so a
        -- single unit occupying slot 9 doesn't get evicted.
        local benchPenalty = 0
        for _, c in ipairs(state.activeCards or {}) do
            if c.id == "espresso_spill" and c.payload then
                benchPenalty += (c.payload.benchPenalty or 0)
            end
        end
        if benchPenalty > 0 then
            state.benchCapOverride = math.max(1, Constants.BENCH_SIZE - benchPenalty)
        else
            state.benchCapOverride = nil
        end
        state.shop = ShopService.RollShop(state.level, 0)
        state.phase = "shop"
        UnitSpawner.ClearAll()
        syncShopVisuals(state)
    elseif node.type == "shop" then
        state.phase = "shopNode"
        -- Spec P0-2: standalone Shop nodes roll with +1 rarity tier shift
        -- compared to the pre-combat shop. Cost tier is clamped inside
        -- ShopService so the player always sees 5 valid slots.
        state.currentShopCostShift = 1
        state.currentShopFreeReroll = CardService.HasFreeRerollFlag(state)
        state.shop = ShopService.RollShop(state.level, 1)
    elseif node.type == "event" then
        state.phase = "eventDraft"
        -- Offer 2 of the 3 event cards
        local rng = function() return math.random() end
        state.pendingDraft = { kind = "event", options = CardDefinitions.sample("event", 2, rng) }
    elseif node.type == "forge" then
        state.phase = "forgeDraft"
        local rng = function() return math.random() end
        state.pendingDraft = { kind = "forge", options = CardDefinitions.sample("forge", 3, rng) }
    end
end

local function onNodeComplete(state: PlayerState)
    RunMapService.MarkCurrentVisited(state)
    local node = RunMapService.CurrentNode(state)
    if not node then return end
    if #node.nextNodeIds == 0 then
        -- dead end (shouldn't happen except at boss)
        state.phase = "victory"
        return
    end
    state.phase = "nodeSelect"
end

-- ---------- handlers ---------- --

function GameManager.HandleBuyUnit(player: Player, slotIdx: number)
    local state = states[player.UserId]
    if not state then return end
    if state.phase ~= "shop" and state.phase ~= "shopNode" then return end
    if type(slotIdx) ~= "number" then return end
    if ShopService.Buy(state, slotIdx) then
        syncShopVisuals(state)
        broadcast(player.UserId)
    end
end

function GameManager.HandleSellUnit(player: Player, source: string, idx: number)
    local state = states[player.UserId]
    if not state then return end
    if state.phase ~= "shop" and state.phase ~= "shopNode" then return end
    if type(source) ~= "string" or type(idx) ~= "number" then return end
    if ShopService.Sell(state, source, idx) then
        if source == "board" then syncShopVisuals(state) end
        broadcast(player.UserId)
    end
end

function GameManager.HandlePlaceUnit(player: Player, payload: any)
    local state = states[player.UserId]
    if not state then return end
    if state.phase ~= "shop" and state.phase ~= "shopNode" then return end
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
    if not state then return end
    if state.phase ~= "shop" and state.phase ~= "shopNode" then return end
    if ShopService.Reroll(state) then
        broadcast(player.UserId)
    end
end

function GameManager.HandleBuyXP(player: Player)
    local state = states[player.UserId]
    if not state then return end
    if state.phase ~= "shop" and state.phase ~= "shopNode" then return end
    if ShopService.BuyXP(state) then
        broadcast(player.UserId)
    end
end

function GameManager.HandleStartCombat(player: Player)
    local state = states[player.UserId]
    if not state or state.phase ~= "shop" then return end
    task.spawn(runCombat, state)
end

-- Replaces the old HandleNextRound. Used by clients clicking "Continue" on
-- the postcombat overlay or "Leave Shop" on a standalone shop node.
function GameManager.HandleContinue(player: Player)
    local state = states[player.UserId]
    if not state then return end
    if state.phase == "postcombat" or state.phase == "shopNode" then
        -- End of shop visit (shopNode branch). The freeReroll half of
        -- Skibidi Portal is consumed here whether it fired or not. The
        -- +1 enemy half persists until actual combat runs.
        if state.phase == "shopNode" and state.currentShopFreeReroll then
            CardService.ClearFreeRerollFlag(state)
        end
        state.currentShopFreeReroll = false
        state.currentShopCostShift = 0
        onNodeComplete(state)
        broadcast(player.UserId)
    end
end

-- Legacy alias so the existing NextRound remote still works.
GameManager.HandleNextRound = GameManager.HandleContinue

function GameManager.HandleSelectNextNode(player: Player, payload: any)
    local state = states[player.UserId]
    if not state or state.phase ~= "nodeSelect" then return end
    if type(payload) ~= "table" or type(payload.nodeId) ~= "string" then return end
    if RunMapService.SelectNext(state, payload.nodeId) then
        enterNode(state, payload.nodeId)
        broadcast(player.UserId)
    end
end

function GameManager.HandleCardChoice(player: Player, payload: any)
    local state = states[player.UserId]
    if not state then return end
    if type(payload) ~= "table" or type(payload.cardId) ~= "string" then return end
    if state.phase ~= "eventDraft" and state.phase ~= "forgeDraft" and state.phase ~= "unitTarget" then return end

    local card = CardDefinitions.CARDS[payload.cardId]
    if not card then return end

    -- If this card was in the pending draft options, verify it was offered.
    if state.phase == "eventDraft" or state.phase == "forgeDraft" then
        local offered = state.pendingDraft and state.pendingDraft.options or {}
        local legal = false
        for _, opt in ipairs(offered) do if opt == payload.cardId then legal = true; break end end
        if not legal then return end
    end

    -- Cards that need a unit target pause here until the client sends the
    -- second-stage CardChoice with targetUnitInstanceId.
    if card.needsUnitTarget and not payload.targetUnitInstanceId then
        state.pendingTarget = { cardId = payload.cardId }
        state.phase = "unitTarget"
        broadcast(player.UserId)
        return
    end

    local ok = CardService.Apply(state, payload.cardId, {
        targetUnitInstanceId = payload.targetUnitInstanceId,
    })
    if ok then
        state.pendingDraft = nil
        state.pendingTarget = nil
        onNodeComplete(state)
        broadcast(player.UserId)
    end
end

function GameManager.HandleOpenCrate(player: Player)
    local state = states[player.UserId]
    if not state then return end
    if #state.pendingCrates == 0 then return end
    local tier = table.remove(state.pendingCrates, 1)
    if not (CrateService and CrateService.Open) then
        broadcast(player.UserId)
        return
    end

    local drop = CrateService.Open(player.UserId, tier)
    if drop then
        state.collection = DataService.Load(player.UserId).collection
        if drop.goldRefund and drop.goldRefund > 0 then
            state.gold += drop.goldRefund
        end
        if Remotes.CrateReveal then
            Remotes.CrateReveal:FireClient(player, drop)
        end
        if LobbyService and drop.upgraded then
            LobbyService.RefreshPedestals(state.collection)
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
    CardDefinitions = require(shared:WaitForChild("CardDefinitions"))
    ShopService = deps.ShopService
    CombatEngine = deps.CombatEngine
    CrateService = deps.CrateService
    LobbyService = deps.LobbyService
    DataService = deps.DataService
    UnitSpawner = deps.UnitSpawner
    RunMapService = deps.RunMapService
    CardService = deps.CardService
    Remotes = deps.Remotes
end

function GameManager.GetState(userId: number)
    return states[userId]
end

local function warpToLobby(player: Player)
    local lobby = workspace:FindFirstChild("LobbyHub")
    if not lobby then return end
    local spawn = lobby:FindFirstChild("LobbySpawn")
    if not spawn or not spawn:IsA("BasePart") then return end
    local character = player.Character
    if not character then return end
    character:PivotTo(CFrame.new(spawn.Position + Vector3.new(0, 4, 0)))
end

function GameManager.OnPlayerAdded(player: Player)
    local state = newState(player.UserId)
    states[player.UserId] = state
    if LobbyService then
        LobbyService.RefreshPedestals(state.collection)
    end
    broadcast(player.UserId)

    if player.Character then
        warpToLobby(player)
    end
    player.CharacterAdded:Connect(function()
        task.wait(0.15)
        warpToLobby(player)
    end)
end

function GameManager.OnPlayerRemoving(player: Player)
    -- Persist run-in-progress before save + release.
    local state = states[player.UserId]
    if state and state.phase ~= "victory" and state.phase ~= "defeat" then
        persistRun(state)
    end
    DataService.Save(player.UserId)
    DataService.Release(player.UserId)
    states[player.UserId] = nil
end

return GameManager
