--!strict
-- Crate opening logic. Open(userId, tier) -> DropResult.
--
-- Each crate rolls a rarity via the per-tier weighted table, then picks a
-- unitId uniformly from all 10 brainrots. If the pulled rarity beats the
-- player's current rarity for that unit, the collection upgrades; otherwise
-- the player gets +3 gold as consolation.
--
-- The module mutates the DataService profile directly. Phase 10's DataStore
-- wrapper keeps the same API so nothing else has to change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrateService = {}

local UnitDefinitions
local DataService

export type CrateTier = "common" | "rare" | "epic" | "legendary"
export type DropResult = {
    unitId: string,
    rarity: string,
    upgraded: boolean,
    goldRefund: number,
    previousRarity: string?,
    tier: string,
}

-- Percent weights per spec. Values are relative (do NOT need to sum to 100
-- since we normalize at roll time).
local CRATE_TABLES = {
    common    = { common=70,  rare=23, epic=6,  legendary=0.9, mythic=0.1 },
    rare      = { common=30,  rare=45, epic=20, legendary=4.5, mythic=0.5 },
    epic      = { common=0,   rare=40, epic=40, legendary=18,  mythic=2   },
    legendary = { common=0,   rare=0,  epic=40, legendary=50,  mythic=10  },
}

local RARITY_RANK = {common=1, rare=2, epic=3, legendary=4, mythic=5}
local CONSOLATION_GOLD = 3

local function rollRarity(tier: string): string
    local weights = CRATE_TABLES[tier]
    if not weights then return "common" end
    local total = 0
    for _, w in pairs(weights) do total += w end
    if total <= 0 then return "common" end

    local roll = math.random() * total
    local acc = 0
    -- Deterministic iteration order: walk rarity ladder low-to-high.
    for _, rarity in ipairs({"common", "rare", "epic", "legendary", "mythic"}) do
        local w = weights[rarity] or 0
        acc += w
        if roll <= acc then return rarity end
    end
    return "mythic"
end

local unitIds: { string }? = nil
local function allUnitIds(): { string }
    if unitIds then return unitIds end
    local out = {}
    for uid in pairs(UnitDefinitions) do table.insert(out, uid) end
    table.sort(out)  -- stable ordering for tests
    unitIds = out
    return out
end

function CrateService.Init(deps)
    local shared = deps.Shared
    UnitDefinitions = require(shared:WaitForChild("UnitDefinitions"))
    DataService = deps.DataService
end

function CrateService.InitStandalone()
    local shared = ReplicatedStorage:WaitForChild("Shared")
    UnitDefinitions = require(shared:WaitForChild("UnitDefinitions"))
    -- Caller must pass DataService before Open() is called; test harnesses
    -- plug a mock in via CrateService.SetDataService.
end

function CrateService.SetDataService(ds)
    DataService = ds
end

function CrateService.Open(userId: number, tier: CrateTier | string): DropResult?
    if not UnitDefinitions or not DataService then
        warn("[CrateService] not initialized")
        return nil
    end
    if not CRATE_TABLES[tier] then
        warn("[CrateService] unknown tier: " .. tostring(tier))
        return nil
    end

    local rarity = rollRarity(tier)
    local ids = allUnitIds()
    local unitId = ids[math.random(1, #ids)]

    local profile = DataService.Load(userId)
    local previous = profile.collection[unitId]
    local previousRank = RARITY_RANK[previous] or 0
    local newRank = RARITY_RANK[rarity] or 0

    local upgraded = newRank > previousRank
    local goldRefund = 0

    if upgraded then
        DataService.UpgradeCollection(userId, unitId, rarity)
    else
        goldRefund = CONSOLATION_GOLD
    end

    return {
        unitId = unitId,
        rarity = rarity,
        upgraded = upgraded,
        goldRefund = goldRefund,
        previousRarity = previous,
        tier = tostring(tier),
    }
end

-- Exposed for tests / debugging.
function CrateService.GetDropTable(tier: string)
    return CRATE_TABLES[tier]
end

return CrateService
