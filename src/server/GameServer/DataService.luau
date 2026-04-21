--!strict
-- In-memory DataStore stub. Phase 10 swaps the backing table for a real
-- DataStore + session-lock wrapper. Public API is designed to stay stable
-- across that swap: all calls are synchronous from the caller's perspective,
-- and Load/Save return a success boolean.

local DataService = {}

type Profile = {
    collection: { [string]: string },
    bestRound: number,
    totalWins: number,
    firstPlayed: number,
}

local profiles: { [number]: Profile } = {}

local function newProfile(): Profile
    return {
        collection = {},
        bestRound = 0,
        totalWins = 0,
        firstPlayed = os.time(),
    }
 end

function DataService.Load(userId: number): Profile
    local existing = profiles[userId]
    if existing then return existing end
    local p = newProfile()
    profiles[userId] = p
    return p
end

function DataService.Save(userId: number): boolean
    return profiles[userId] ~= nil
end

function DataService.Release(userId: number)
    profiles[userId] = nil
end

function DataService.UpgradeCollection(userId: number, unitId: string, rarity: string): boolean
    local p = DataService.Load(userId)
    p.collection[unitId] = rarity
    return true
end

function DataService.Init()
end

return DataService
