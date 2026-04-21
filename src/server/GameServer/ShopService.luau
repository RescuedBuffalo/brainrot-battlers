--!strict
-- Pure(ish) shop logic. Functions take a PlayerState table, mutate it, and
-- return a success boolean. GameManager owns state ownership + broadcasting;
-- this module only knows the rules (rolls, costs, 3-combine, level-up).
--
-- Bench is a fixed-size sparse list (nil slots allowed). Board is a dense
-- array with #board capped at state.level.
--
-- 3-combine rule: 3 units with matching {unitId, star} anywhere on bench OR
-- board merge into 1 unit at star+1, inheriting the best rarity of the three.
-- Cascades up to star 3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")

local ShopService = {}

local Constants
local UnitDefinitions
local ShopOdds
local LevelXP

local RARITY_RANK = {common=1, rare=2, epic=3, legendary=4, mythic=5}

local function bestRarity(a: string, b: string): string
    return (RARITY_RANK[a] or 0) >= (RARITY_RANK[b] or 0) and a or b
end

local POOL: {[number]: {string}}? = nil
local function pool()
    if POOL then return POOL end
    local p = {[1]={}, [2]={}, [3]={}, [4]={}, [5]={}}
    for uid, def in pairs(UnitDefinitions) do
        if p[def.cost] then table.insert(p[def.cost], uid) end
    end
    POOL = p
    return p
end

local function firstEmptyBench(state): number?
    for i = 1, Constants.BENCH_SIZE do
        if state.bench[i] == nil then return i end
    end
    return nil
end

local function benchCount(state): number
    local n = 0
    for _, b in pairs(state.bench) do
        if b then n += 1 end
    end
    return n
end

local function findMatches(state, unitId: string, star: number)
    local matches = {}
    for i, b in pairs(state.bench) do
        if b and b.unitId == unitId and b.star == star then
            table.insert(matches, {loc="bench", idx=i, unit=b})
        end
    end
    for i = 1, #state.board do
        local b = state.board[i]
        if b and b.unitId == unitId and b.star == star then
            table.insert(matches, {loc="board", idx=i, unit=b})
        end
    end
    return matches
end

local function removeAt(state, loc: string, idx: number)
    if loc == "bench" then
        state.bench[idx] = nil
    elseif loc == "board" then
        table.remove(state.board, idx)
    end
end

local function addToBench(state, unit): boolean
    local slot = firstEmptyBench(state)
    if not slot then return false end
    state.bench[slot] = unit
    return true
end

-- Combine cascading: merge 3 identical units (unitId+star) into 1 at star+1.
-- Returns number of combines performed (cascades included).
local function tryCombine(state, unitId: string, star: number): number
    if star >= 3 then return 0 end
    local matches = findMatches(state, unitId, star)
    if #matches < 3 then return 0 end

    local take = { matches[1], matches[2], matches[3] }
    local rarity = take[1].unit.rarity
    for i = 2, 3 do
        rarity = bestRarity(rarity, take[i].unit.rarity)
    end

    -- Remove in deterministic order: board entries highest-idx first (so
    -- table.remove doesn't shift earlier matches), then bench entries.
    table.sort(take, function(a, b)
        if a.loc ~= b.loc then return a.loc == "board" end
        return a.idx > b.idx
    end)
    for _, m in ipairs(take) do
        removeAt(state, m.loc, m.idx)
    end

    local merged = { unitId = unitId, star = star + 1, rarity = rarity }
    addToBench(state, merged)

    return 1 + tryCombine(state, unitId, star + 1)
end

-- Level-up cascading from accumulated XP.
local function processLevelUps(state)
    while state.level < Constants.MAX_LEVEL do
        local nextLvl = state.level + 1
        local threshold = LevelXP[nextLvl]
        if threshold == nil or state.xp < threshold then break end
        state.xp -= threshold
        state.level = nextLvl
    end
    if state.level >= Constants.MAX_LEVEL then
        state.xp = 0
    end
end

-- ---------- public API ---------- --

function ShopService.Init(deps)
    local shared = deps.Shared
    Constants = require(shared:WaitForChild("Constants"))
    UnitDefinitions = require(shared:WaitForChild("UnitDefinitions"))
    ShopOdds = require(shared:WaitForChild("ShopOdds"))
    LevelXP = require(shared:WaitForChild("LevelXP"))
end

function ShopService.InitStandalone()
    Constants = require(sharedFolder:WaitForChild("Constants"))
    UnitDefinitions = require(sharedFolder:WaitForChild("UnitDefinitions"))
    ShopOdds = require(sharedFolder:WaitForChild("ShopOdds"))
    LevelXP = require(sharedFolder:WaitForChild("LevelXP"))
end

function ShopService.RollShop(level: number)
    local p = pool()
    local lvl = math.clamp(level, 1, 8)
    local odds = ShopOdds[lvl]
    local slots = {}
    for _ = 1, Constants.SHOP_SIZE do
        local roll = math.random(1, 100)
        local acc = 0
        local chosenCost = 1
        for cost = 1, 5 do
            acc += odds[cost]
            if roll <= acc then chosenCost = cost; break end
        end
        local tier = p[chosenCost]
        if tier and #tier > 0 then
            table.insert(slots, { unitId = tier[math.random(1, #tier)], sold = false })
        else
            table.insert(slots, { unitId = nil, sold = true })
        end
    end
    return slots
end

function ShopService.Buy(state, slotIdx: number): boolean
    local slot = state.shop[slotIdx]
    if not slot or slot.sold or not slot.unitId then return false end
    local def = UnitDefinitions[slot.unitId]
    if not def then return false end
    if state.gold < def.cost then return false end

    -- Full bench: only allow if buying triggers an immediate combine.
    if firstEmptyBench(state) == nil then
        local matches = findMatches(state, slot.unitId, 1)
        if #matches < 2 then return false end
    end

    state.gold -= def.cost
    state.xp += Constants.XP_PER_BUY
    processLevelUps(state)

    local unit = { unitId = slot.unitId, star = 1, rarity = "common" }
    if firstEmptyBench(state) == nil then
        -- Bench full + combine imminent: force-combine by inserting into a
        -- synthetic 4th slot then immediately consuming.
        local matches = findMatches(state, slot.unitId, 1)
        -- Remove 2 existing matches + promote to star 2 via the new unit
        local take = { matches[1], matches[2] }
        table.sort(take, function(a, b)
            if a.loc ~= b.loc then return a.loc == "board" end
            return a.idx > b.idx
        end)
        local rarity = bestRarity(unit.rarity, take[1].unit.rarity)
        rarity = bestRarity(rarity, take[2].unit.rarity)
        for _, m in ipairs(take) do removeAt(state, m.loc, m.idx) end
        addToBench(state, { unitId = slot.unitId, star = 2, rarity = rarity })
        tryCombine(state, slot.unitId, 2)
    else
        addToBench(state, unit)
        tryCombine(state, slot.unitId, 1)
    end

    slot.sold = true
    slot.unitId = nil
    return true
end

local SELL_MULT = { [1] = 1, [2] = 3, [3] = 5 }

function ShopService.SellValue(unit): number
    local def = UnitDefinitions[unit.unitId]
    if not def then return 0 end
    return def.cost * (SELL_MULT[unit.star] or 1)
end

function ShopService.Sell(state, source: string, index: number): boolean
    local unit
    if source == "bench" then
        unit = state.bench[index]
        if not unit then return false end
        state.bench[index] = nil
    elseif source == "board" then
        unit = state.board[index]
        if not unit then return false end
        table.remove(state.board, index)
    else
        return false
    end
    state.gold += ShopService.SellValue(unit)
    return true
end

function ShopService.Reroll(state): boolean
    if state.gold < Constants.REROLL_COST then return false end
    state.gold -= Constants.REROLL_COST
    state.shop = ShopService.RollShop(state.level)
    return true
end

function ShopService.BuyXP(state): boolean
    if state.level >= Constants.MAX_LEVEL then return false end
    if state.gold < Constants.XP_COST then return false end
    state.gold -= Constants.XP_COST
    state.xp += Constants.XP_PER_BUY
    processLevelUps(state)
    return true
end

-- Move a unit between bench and board. x,y only matter when toLoc == "board".
-- Enforces board size <= level and player rows only (y in PLAYER_ROWS).
function ShopService.PlaceUnit(state, fromLoc: string, fromIdx: number, toLoc: string, toIdx: number, x: number?, y: number?): boolean
    if fromLoc == "bench" then
        local unit = state.bench[fromIdx]
        if not unit then return false end
        if toLoc == "board" then
            if not x or not y then return false end
            if x < 0 or x >= Constants.COLS then return false end
            local allowed = false
            for _, py in ipairs(Constants.PLAYER_ROWS) do
                if y == py then allowed = true; break end
            end
            if not allowed then return false end
            -- tile occupied?
            for _, b in ipairs(state.board) do
                if b.x == x and b.y == y then return false end
            end
            if #state.board >= state.level then return false end
            state.bench[fromIdx] = nil
            table.insert(state.board, {
                unitId = unit.unitId, star = unit.star, rarity = unit.rarity,
                x = x, y = y,
            })
            return true
        elseif toLoc == "bench" then
            if state.bench[toIdx] == nil then
                state.bench[toIdx] = unit
                state.bench[fromIdx] = nil
            else
                state.bench[toIdx], state.bench[fromIdx] = unit, state.bench[toIdx]
            end
            return true
        end
    elseif fromLoc == "board" then
        local unit = state.board[fromIdx]
        if not unit then return false end
        if toLoc == "bench" then
            if state.bench[toIdx] ~= nil then return false end
            state.bench[toIdx] = { unitId = unit.unitId, star = unit.star, rarity = unit.rarity }
            table.remove(state.board, fromIdx)
            return true
        elseif toLoc == "board" then
            if not x or not y then return false end
            local allowed = false
            for _, py in ipairs(Constants.PLAYER_ROWS) do
                if y == py then allowed = true; break end
            end
            if not allowed then return false end
            -- Swap with occupant if any, else move
            local occupant
            for i, b in ipairs(state.board) do
                if b.x == x and b.y == y and i ~= fromIdx then occupant = i; break end
            end
            if occupant then
                state.board[occupant].x, state.board[occupant].y = unit.x, unit.y
            end
            unit.x, unit.y = x, y
            return true
        end
    end
    return false
end

-- Mark ShopService as initialized (for debug/assertion).
function ShopService.IsReady(): boolean
    return Constants ~= nil
end

return ShopService
