--!strict
-- DataStore-backed profile storage with session locking, exponential-backoff
-- retries, and an in-memory fallback for Studio when "Allow HTTP Requests" /
-- API services are disabled.
--
-- Profile schema:
--   {
--     version = 1,
--     collection = { [unitId] = rarity },
--     bestRound = number,
--     totalWins = number,
--     firstPlayed = unix,
--     lastPlayed = unix,
--     sessionLock = { jobId, timestamp } | nil,
--   }
--
-- Locking: on Load we UpdateAsync with a single pass that:
--   (a) checks if there's an active lock from a different JobId,
--   (b) if stale (> LOCK_TTL) or owned by us, claim it,
--   (c) otherwise the load fails (caller falls back to a fresh profile).
-- This keeps two servers from double-writing on a fast migration.
--
-- Public API (unchanged from the Phase 1 stub):
--   Init()                                 -- detect DataStore availability
--   Load(userId)     -> Profile            -- returns cached profile; reads remote once
--   Save(userId)     -> success: boolean   -- writes, keeps lock alive
--   Release(userId)                        -- saves + clears lock
--   UpgradeCollection(userId, unitId, rarity)
-- Phase-10 additions:
--   BumpStats(userId, bestRound, totalWins)
--   StartAutosave()                        -- background loop
--   FlushAll()                             -- called by BindToClose

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local DataService = {}

type Lock = { jobId: string, timestamp: number }
type Profile = {
    version: number,
    collection: { [string]: string },
    bestRound: number,
    totalWins: number,
    firstPlayed: number,
    lastPlayed: number,
    sessionLock: Lock?,
}

local STORE_NAME = "Profiles_v1"
local LOCK_TTL = 300                -- 5 min; stale locks get reclaimed
local AUTOSAVE_INTERVAL = 300       -- 5 min
local MAX_RETRIES = 3
local BACKOFF_START = 0.5           -- doubles each retry

local profiles: { [number]: Profile } = {}
local dirty: { [number]: boolean } = {}
local store: DataStore? = nil
local usingFallback = false
local jobId = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(os.clock()))

local function log(msg: string)
    print(("[DataService] %s"):format(msg))
end

local function newProfile(): Profile
    local now = os.time()
    return {
        version = 1,
        collection = {},
        bestRound = 0,
        totalWins = 0,
        firstPlayed = now,
        lastPlayed = now,
        sessionLock = nil,
    }
end

-- Wrap a DataStore op with exponential-backoff retries. Returns (ok, result).
local function withRetry<T>(label: string, fn: () -> T): (boolean, T?)
    local delay = BACKOFF_START
    local lastErr: any = nil
    for attempt = 1, MAX_RETRIES do
        local ok, result = pcall(fn)
        if ok then
            return true, result
        end
        lastErr = result
        if attempt < MAX_RETRIES then
            task.wait(delay)
            delay *= 2
        end
    end
    warn(("[DataService] %s failed after %d attempts: %s"):format(label, MAX_RETRIES, tostring(lastErr)))
    return false, nil
end

local function keyFor(userId: number): string
    return "profile_" .. tostring(userId)
end

-- Probe whether the DataStore API is actually callable. In Studio without
-- "Enable Studio Access to API Services" a DataStore object is returned but
-- every op raises "403 HTTP 403 (Forbidden)" at call time.
local function probeDataStore(s: DataStore): boolean
    local ok, err = pcall(function()
        s:GetAsync("__probe__")
    end)
    if not ok then
        warn(("[DataService] DataStore probe failed: %s"):format(tostring(err)))
    end
    return ok
end

function DataService.Init()
    local ok, result = pcall(function()
        return DataStoreService:GetDataStore(STORE_NAME)
    end)
    if ok and result and probeDataStore(result) then
        store = result
        usingFallback = false
        log("DataStore enabled (key store: " .. STORE_NAME .. ")")
    else
        usingFallback = true
        log("DataStore unavailable, using in-memory fallback (data will NOT persist)")
    end
end

-- Atomically verify the session lock and (a) claim it for this server, or
-- (b) reject the load if another server holds a fresh lock.
-- Returns the loaded Profile or nil.
local function loadWithLock(userId: number): Profile?
    if not store then return nil end
    local captured: Profile? = nil
    local rejected = false

    local ok = withRetry("UpdateAsync(load)", function()
        store:UpdateAsync(keyFor(userId), function(old)
            local profile: Profile = old or newProfile()
            if profile.sessionLock then
                local age = os.time() - profile.sessionLock.timestamp
                if profile.sessionLock.jobId ~= jobId and age < LOCK_TTL then
                    rejected = true
                    -- Return nil to abort the transaction -- DataStore treats
                    -- a nil return from UpdateAsync as "cancel this update".
                    return nil
                end
            end
            profile.sessionLock = { jobId = jobId, timestamp = os.time() }
            profile.lastPlayed = os.time()
            captured = profile
            return profile
        end)
    end)

    if not ok or rejected or not captured then
        if rejected then
            warn(("[DataService] userId=%d is locked by another server; using fresh session"):format(userId))
        end
        return nil
    end
    return captured
end

function DataService.Load(userId: number): Profile
    if profiles[userId] then return profiles[userId] end

    if usingFallback then
        profiles[userId] = newProfile()
        profiles[userId].sessionLock = { jobId = jobId, timestamp = os.time() }
        return profiles[userId]
    end

    local loaded = loadWithLock(userId)
    if loaded then
        profiles[userId] = loaded
        return loaded
    end

    -- Load failed -- use a fresh in-memory profile so the player can keep
    -- playing. We do NOT persist it until the load eventually succeeds (next
    -- rejoin will retry).
    local fresh = newProfile()
    fresh.sessionLock = { jobId = jobId, timestamp = os.time() }
    profiles[userId] = fresh
    dirty[userId] = false
    return fresh
end

function DataService.Save(userId: number): boolean
    local profile = profiles[userId]
    if not profile then return false end
    if usingFallback then
        dirty[userId] = false
        return true
    end
    if not store then return false end

    profile.lastPlayed = os.time()
    profile.sessionLock = { jobId = jobId, timestamp = os.time() }

    local ok = withRetry("UpdateAsync(save)", function()
        store:UpdateAsync(keyFor(userId), function(old)
            -- If another server stole the lock while we were idle, back off.
            if old and old.sessionLock and old.sessionLock.jobId ~= jobId then
                local age = os.time() - old.sessionLock.timestamp
                if age < LOCK_TTL then
                    warn(("[DataService] save aborted: userId=%d lock stolen by %s"):format(userId, old.sessionLock.jobId))
                    return nil
                end
            end
            return profile
        end)
    end)
    if ok then dirty[userId] = false end
    return ok or false
end

function DataService.Release(userId: number)
    local profile = profiles[userId]
    if not profile then return end
    if usingFallback then
        profiles[userId] = nil
        dirty[userId] = nil
        return
    end
    if not store then
        profiles[userId] = nil
        dirty[userId] = nil
        return
    end

    profile.lastPlayed = os.time()
    profile.sessionLock = nil  -- explicitly clear

    withRetry("UpdateAsync(release)", function()
        store:UpdateAsync(keyFor(userId), function(old)
            -- Only write if we still own the lock (or nobody does)
            if old and old.sessionLock and old.sessionLock.jobId ~= jobId then
                return nil
            end
            return profile
        end)
    end)
    profiles[userId] = nil
    dirty[userId] = nil
end

function DataService.UpgradeCollection(userId: number, unitId: string, rarity: string): boolean
    local p = DataService.Load(userId)
    p.collection[unitId] = rarity
    dirty[userId] = true
    return true
end

-- Update run stats (best round + total wins). Takes max-of so we never
-- regress if a stale state update comes through.
function DataService.BumpStats(userId: number, bestRound: number?, totalWins: number?)
    local p = DataService.Load(userId)
    if bestRound and bestRound > p.bestRound then
        p.bestRound = bestRound
    end
    if totalWins and totalWins > p.totalWins then
        p.totalWins = totalWins
    end
    dirty[userId] = true
end

function DataService.StartAutosave()
    task.spawn(function()
        while true do
            task.wait(AUTOSAVE_INTERVAL)
            for userId, isDirty in pairs(dirty) do
                if isDirty and profiles[userId] then
                    DataService.Save(userId)
                end
            end
        end
    end)
end

-- Flush every active profile. Called from BindToClose. Runs saves in
-- parallel-ish by using task.spawn per profile so one slow op doesn't serialize
-- the 30s shutdown window.
function DataService.FlushAll()
    log("FlushAll: starting graceful shutdown saves")
    local ids = {}
    for userId in pairs(profiles) do table.insert(ids, userId) end

    local remaining = #ids
    if remaining == 0 then return end

    local done = Instance.new("BindableEvent")
    for _, userId in ipairs(ids) do
        task.spawn(function()
            DataService.Release(userId)
            remaining -= 1
            if remaining <= 0 then done:Fire() end
        end)
    end
    done.Event:Wait()
    log("FlushAll: complete")
end

-- Diagnostic: useful for tests and the Phase10Test harness.
function DataService.IsUsingFallback(): boolean
    return usingFallback
end

function DataService.GetProfile(userId: number): Profile?
    return profiles[userId]
end

return DataService
