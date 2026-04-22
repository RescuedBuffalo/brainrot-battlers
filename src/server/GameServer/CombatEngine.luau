--!strict
-- Tick-based auto-battle resolver. Pure logic, no Workspace dependency:
-- takes a player board and enemy board (lists of {unitId, star, rarity, x, y}),
-- runs the fight headlessly, and returns a Result including an event stream
-- the client can replay as visuals.
--
-- Each tick advances TICK_RATE seconds. Every alive actor acts once per tick,
-- ordered by effective attack speed (highest first). Actions by priority:
--   1. Cast ability (if mana >= maxMana)
--   2. Attack nearest enemy (if in range and atkCd ready)
--   3. Move one tile toward nearest enemy (if moveCd ready)
-- Deaths are emitted the moment HP <= 0 but the tile stays occupied until the
-- next tick starts (per spec: removed from logic "the tick after death").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatEngine = {}

export type Outcome = "win" | "loss" | "timeout"
export type Result = {
    outcome: Outcome,
    ticks: number,
    events: { any },
    survivors: { any },
    goldStolen: number,
    playerTraits: { [string]: number },
    enemyTraits: { [string]: number },
}

local Constants
local UnitDefinitions
local TraitDefinitions
local RarityDefinitions
local AbilityService

-- ---------- helpers ---------- --

local function tileKey(x: number, y: number): string
    return x .. "," .. y
end

local function chebyshev(a, b): number
    return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function emit(engine, evt)
    evt.tick = engine.tick
    table.insert(engine.events, evt)
end

local function allLiving(engine)
    local out = {}
    for _, a in ipairs(engine.actorsList) do
        if not a.dead then table.insert(out, a) end
    end
    return out
end

local function enemiesOf(engine, actor)
    local out = {}
    for _, a in ipairs(engine.actorsList) do
        if not a.dead and a.side ~= actor.side then
            table.insert(out, a)
        end
    end
    return out
end

local function alliesOf(engine, actor)
    local out = {}
    for _, a in ipairs(engine.actorsList) do
        if not a.dead and a.side == actor.side then
            table.insert(out, a)
        end
    end
    return out
end

local function findClosest(engine, actor)
    local best, bestD = nil, math.huge
    for _, o in ipairs(engine.actorsList) do
        if not o.dead and o.side ~= actor.side then
            local d = chebyshev(actor, o)
            if d < bestD then
                bestD = d
                best = o
            end
        end
    end
    return best, bestD
end

local function findLowestHp(engine, actor)
    local best, bestHp = nil, math.huge
    for _, o in ipairs(engine.actorsList) do
        if not o.dead and o.side ~= actor.side and o.hp < bestHp then
            bestHp = o.hp
            best = o
        end
    end
    return best
end

local function findByScore(engine, actor, scoreFn)
    local best, bestScore = nil, -math.huge
    for _, o in ipairs(engine.actorsList) do
        if not o.dead and o.side ~= actor.side then
            local s = scoreFn(o)
            if s > bestScore then
                bestScore = s
                best = o
            end
        end
    end
    return best
end

local function dealDamage(engine, source, target, amount, crit)
    if target.dead then return end
    local remaining = amount
    if target.shield > 0 then
        local absorbed = math.min(target.shield, remaining)
        target.shield -= absorbed
        remaining -= absorbed
    end
    target.hp -= remaining
    emit(engine, {
        kind = "dmg",
        source = source and source.id,
        target = target.id,
        amount = amount,
        crit = crit or false,
        hp = math.max(0, target.hp),
        shield = target.shield,
    })
    if target.hp <= 0 then
        target.dead = true
        target.hp = 0
        emit(engine, {
            kind = "death",
            target = target.id,
        })
    end
end

-- Teleport into a free tile adjacent to target on the side opposite the caster.
-- Fallback order: directly behind, diagonals, target's current tile if caster
-- displaces there (only happens if target is about to die).
local function teleportBehind(engine, actor, target)
    local behindY
    if target.side == "player" then
        behindY = target.y + 1
    else
        behindY = target.y - 1
    end
    local candidates = {
        {target.x, behindY},
        {target.x - 1, behindY},
        {target.x + 1, behindY},
        {target.x - 1, target.y},
        {target.x + 1, target.y},
    }
    for _, c in ipairs(candidates) do
        local nx, ny = c[1], c[2]
        if nx >= 0 and nx < Constants.COLS and ny >= 0 and ny < Constants.ROWS then
            local occupant = engine.tileMap[tileKey(nx, ny)]
            if occupant == nil or occupant == actor.id then
                engine.tileMap[tileKey(actor.x, actor.y)] = nil
                actor.x, actor.y = nx, ny
                engine.tileMap[tileKey(nx, ny)] = actor.id
                emit(engine, {
                    kind = "move",
                    source = actor.id,
                    teleport = true,
                    to = {nx, ny},
                })
                return
            end
        end
    end
end

-- ---------- trait resolution ---------- --

-- mods.traitThresholdReduction[traitId] (optional) lets a forge card
-- (ohio_energy: -1 threshold) make tiers activate with fewer units.
local function resolveTraits(boardUnits, mods)
    mods = mods or {}
    local thresholdReduction = mods.traitThresholdReduction or {}
    local counts: {[string]: {[string]: true}} = {}
    for _, u in ipairs(boardUnits) do
        local def = UnitDefinitions[u.unitId]
        if def then
            for _, traitId in ipairs(def.traits) do
                counts[traitId] = counts[traitId] or {}
                counts[traitId][u.unitId] = true
            end
        end
    end
    local active: {[string]: number} = {}
    for traitId, unitSet in pairs(counts) do
        local n = 0
        for _ in pairs(unitSet) do n += 1 end
        local td = TraitDefinitions[traitId]
        if td then
            local reduction = thresholdReduction[traitId] or 0
            local activeTier = nil
            for i, tier in ipairs(td.tiers) do
                local required = math.max(1, tier[1] - reduction)
                if n >= required then activeTier = i - 1 end
            end
            if activeTier ~= nil then active[traitId] = activeTier end
        end
    end
    return active
end

-- Phase 12: applyCardMods bakes card effects into the actor's stats after
-- base + trait math. Mods come from CardService.BuildCombatMods.
--   mods.traitAdBonus[trait]   -> fractional AD bonus for matching units
--   mods.traitAsBonus[trait]   -> fractional AS bonus (next-combat only)
--   mods.unitHpBonuses[unitId] -> flat HP bonus for matching units
local function applyCardMods(actor, mods)
    if not mods then return end
    local def = UnitDefinitions[actor.unitId]
    if not def then return end

    for _, trait in ipairs(def.traits) do
        local adBonus = (mods.traitAdBonus or {})[trait]
        if adBonus and adBonus > 0 then
            actor.atk = actor.atk * (1 + adBonus)
        end
        local asBonus = (mods.traitAsBonus or {})[trait]
        if asBonus and asBonus > 0 then
            actor.attackSpeed = actor.attackSpeed * (1 + asBonus)
        end
    end

    local hpBonus = (mods.unitHpBonuses or {})[actor.unitId]
    if hpBonus and hpBonus > 0 then
        actor.hp += hpBonus
        actor.maxHp += hpBonus
    end
end

local function applyTraits(actor, activeTiers)
    local def = UnitDefinitions[actor.unitId]
    for _, trait in ipairs(def.traits) do
        local tier = activeTiers[trait]
        if tier ~= nil then
            if trait == "italian" then
                if tier == 0 then actor.atk *= 1.2 end
                if tier == 1 then actor.atk *= 1.5 end
            elseif trait == "ohio" then
                if tier == 0 then actor.crit = 0.2; actor.critMult = 1.5 end
                if tier == 1 then actor.crit = 0.4; actor.critMult = 2.0 end
            elseif trait == "sigma" then
                if tier == 0 then actor.startMana = 25 end
                if tier == 1 then actor.startMana = 50 end
            elseif trait == "brawler" then
                if tier == 0 then actor.hp += 300; actor.maxHp += 300 end
                if tier == 1 then actor.hp += 800; actor.maxHp += 800 end
            elseif trait == "ranged" then
                if tier == 0 then actor.attackSpeed *= 1.25 end
                if tier == 1 then actor.attackSpeed *= 1.55 end
            elseif trait == "assassin" then
                if tier == 0 then actor.assassinMult = 2 end
                if tier == 1 then actor.assassinMult = 3 end
            elseif trait == "mage" then
                if tier == 0 then actor.abilityMult = 1.3 end
            end
        end
    end
end

local function buildActor(id: number, side: string, unitData, activeTiers, cardMods)
    local def = UnitDefinitions[unitData.unitId]
    assert(def, "buildActor: unknown unitId " .. tostring(unitData.unitId))
    local starMult = Constants.STAR_MULT[unitData.star] or 1
    local rarDef = RarityDefinitions[unitData.rarity]
    local rarMult = (rarDef and rarDef.statMult) or 1

    local actor = {
        id = id,
        side = side,
        unitId = unitData.unitId,
        cost = def.cost,
        star = unitData.star,
        rarity = unitData.rarity,
        x = unitData.x,
        y = unitData.y,
        hp = def.hp * starMult * rarMult,
        maxHp = def.hp * starMult * rarMult,
        atk = def.atk * starMult * rarMult,
        attackSpeed = def.attackSpeed,
        range = def.range,
        mana = 0,
        maxMana = def.maxMana,
        startMana = 0,
        atkCd = 0,
        moveCd = 0,
        shield = 0,
        stunned = 0,
        asBuff = 0,
        asBuffMult = 1.0,
        hasAttacked = false,
        dead = false,
        crit = 0,
        critMult = 1.0,
        abilityMult = 1.0,
        assassinMult = 1.0,
    }

    applyTraits(actor, activeTiers)
    -- Player-side card mods stack on top of trait-adjusted stats.
    if side == "player" and cardMods then
        applyCardMods(actor, cardMods)
    end
    actor.mana = actor.startMana
    return actor
end

-- ---------- actions ---------- --

local function effectiveAS(actor): number
    return actor.attackSpeed * actor.asBuffMult
end

local function tryMove(engine, actor, target): boolean
    if actor.moveCd > 0 then return false end
    local dx = target.x > actor.x and 1 or (target.x < actor.x and -1 or 0)
    local dy = target.y > actor.y and 1 or (target.y < actor.y and -1 or 0)
    if dx == 0 and dy == 0 then return false end

    local function canMove(nx, ny)
        if nx < 0 or nx >= Constants.COLS or ny < 0 or ny >= Constants.ROWS then
            return false
        end
        return engine.tileMap[tileKey(nx, ny)] == nil
    end

    local candidates = {}
    if dx ~= 0 and dy ~= 0 then
        table.insert(candidates, {actor.x + dx, actor.y + dy})
        table.insert(candidates, {actor.x + dx, actor.y})
        table.insert(candidates, {actor.x, actor.y + dy})
    elseif dx ~= 0 then
        table.insert(candidates, {actor.x + dx, actor.y})
        table.insert(candidates, {actor.x + dx, actor.y - 1})
        table.insert(candidates, {actor.x + dx, actor.y + 1})
    else
        table.insert(candidates, {actor.x, actor.y + dy})
        table.insert(candidates, {actor.x - 1, actor.y + dy})
        table.insert(candidates, {actor.x + 1, actor.y + dy})
    end

    for _, c in ipairs(candidates) do
        if canMove(c[1], c[2]) then
            local fromX, fromY = actor.x, actor.y
            engine.tileMap[tileKey(fromX, fromY)] = nil
            actor.x, actor.y = c[1], c[2]
            engine.tileMap[tileKey(c[1], c[2])] = actor.id
            actor.moveCd = Constants.MOVE_COOLDOWN
            emit(engine, {
                kind = "move",
                source = actor.id,
                from = {fromX, fromY},
                to = {c[1], c[2]},
            })
            return true
        end
    end
    return false
end

local function tryAttack(engine, actor, target): boolean
    if actor.atkCd > 0 then return false end
    if chebyshev(actor, target) > actor.range then return false end

    local dmg = actor.atk
    local isCrit = false
    if not actor.hasAttacked and actor.assassinMult > 1 then
        dmg *= actor.assassinMult
        isCrit = true
    end
    actor.hasAttacked = true
    if actor.crit > 0 and math.random() < actor.crit then
        dmg *= actor.critMult
        isCrit = true
    end

    if actor.range > 1 then
        emit(engine, {
            kind = "shoot",
            source = actor.id,
            target = target.id,
        })
    end

    dealDamage(engine, actor, target, dmg, isCrit)
    actor.mana = math.min(actor.maxMana, actor.mana + Constants.ATTACK_MANA_GAIN)
    local as = math.max(0.01, effectiveAS(actor))
    actor.atkCd = 1 / as
    return true
end

-- ---------- main loop ---------- --

local function attachHelpers(engine)
    engine.helpers = {
        chebyshev = chebyshev,
        dealDamage = dealDamage,
        emit = emit,
        findClosest = findClosest,
        findLowestHp = findLowestHp,
        findByScore = findByScore,
        teleportBehind = teleportBehind,
        enemiesOf = enemiesOf,
        alliesOf = alliesOf,
        allLiving = allLiving,
    }
end

local function purgeDead(engine)
    for _, a in ipairs(engine.actorsList) do
        if a.dead then
            local k = tileKey(a.x, a.y)
            if engine.tileMap[k] == a.id then
                engine.tileMap[k] = nil
            end
        end
    end
end

function CombatEngine.Init(deps)
    local shared = deps.Shared
    Constants = require(shared:WaitForChild("Constants"))
    UnitDefinitions = require(shared:WaitForChild("UnitDefinitions"))
    TraitDefinitions = require(shared:WaitForChild("TraitDefinitions"))
    RarityDefinitions = require(shared:WaitForChild("RarityDefinitions"))
    AbilityService = deps.AbilityService
end

-- Standalone init path for headless tests that don't go through Main.
function CombatEngine.InitStandalone(abilityService)
    local shared = ReplicatedStorage:WaitForChild("Shared")
    Constants = require(shared:WaitForChild("Constants"))
    UnitDefinitions = require(shared:WaitForChild("UnitDefinitions"))
    TraitDefinitions = require(shared:WaitForChild("TraitDefinitions"))
    RarityDefinitions = require(shared:WaitForChild("RarityDefinitions"))
    AbilityService = abilityService
end

function CombatEngine.Resolve(playerBoard, enemyBoard, round: number?, cardMods: any?): Result
    assert(Constants, "CombatEngine.Init must be called first")
    cardMods = cardMods or {}
    local engine = {
        tick = 0,
        actors = {},
        actorsList = {},
        tileMap = {},
        events = {},
        round = round or 1,
        goldStolen = 0,
        playerTraits = resolveTraits(playerBoard, cardMods),
        enemyTraits = resolveTraits(enemyBoard),  -- enemies never see player mods
        cardMods = cardMods,
    }
    attachHelpers(engine)

    local nextId = 1
    for _, u in ipairs(playerBoard) do
        local a = buildActor(nextId, "player", u, engine.playerTraits, cardMods)
        engine.actors[nextId] = a
        table.insert(engine.actorsList, a)
        engine.tileMap[tileKey(a.x, a.y)] = nextId
        nextId += 1
    end
    for _, u in ipairs(enemyBoard) do
        local a = buildActor(nextId, "enemy", u, engine.enemyTraits, nil)
        engine.actors[nextId] = a
        table.insert(engine.actorsList, a)
        engine.tileMap[tileKey(a.x, a.y)] = nextId
        nextId += 1
    end

    while engine.tick < Constants.COMBAT_MAX_TICKS do
        purgeDead(engine)

        local alivePlayers, aliveEnemies = 0, 0
        for _, a in ipairs(engine.actorsList) do
            if not a.dead then
                if a.side == "player" then alivePlayers += 1 else aliveEnemies += 1 end
            end
        end
        if alivePlayers == 0 or aliveEnemies == 0 then break end

        local ordered = {}
        for _, a in ipairs(engine.actorsList) do
            if not a.dead then table.insert(ordered, a) end
        end
        table.sort(ordered, function(a, b) return effectiveAS(a) > effectiveAS(b) end)

        for _, actor in ipairs(ordered) do
            if actor.dead then continue end

            actor.atkCd = math.max(0, actor.atkCd - Constants.TICK_RATE)
            actor.moveCd = math.max(0, actor.moveCd - Constants.TICK_RATE)

            if actor.stunned > 0 then
                actor.stunned -= 1
                continue
            end
            if actor.asBuff > 0 then
                actor.asBuff -= 1
                if actor.asBuff <= 0 then actor.asBuffMult = 1.0 end
            end

            if actor.mana >= actor.maxMana then
                emit(engine, { kind = "ability", source = actor.id })
                if AbilityService then
                    AbilityService.Cast(engine, actor)
                end
                actor.mana = 0

                -- Tralalero Surge hook: when a unit with the configured
                -- source trait casts, all allies of allyTrait gain mana.
                -- cardMods.manaShare is set up by CardService.BuildCombatMods.
                local share = engine.cardMods and engine.cardMods.manaShare
                if share and actor.side == "player" then
                    local def = UnitDefinitions[actor.unitId]
                    local hasSource = false
                    if def and def.traits then
                        for _, t in ipairs(def.traits) do
                            if t == share.sourceTrait then hasSource = true; break end
                        end
                    end
                    if hasSource then
                        for _, other in ipairs(engine.actorsList) do
                            if not other.dead and other.side == "player" and other.id ~= actor.id then
                                local oDef = UnitDefinitions[other.unitId]
                                if oDef then
                                    for _, t in ipairs(oDef.traits) do
                                        if t == share.allyTrait then
                                            other.mana = math.min(other.maxMana, other.mana + share.amount)
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                continue
            end

            local target = findClosest(engine, actor)
            if not target then continue end

            local dist = chebyshev(actor, target)
            if dist <= actor.range then
                tryAttack(engine, actor, target)
            else
                tryMove(engine, actor, target)
            end
        end

        engine.tick += 1
    end

    local alivePlayers, aliveEnemies = 0, 0
    local survivors = {}
    for _, a in ipairs(engine.actorsList) do
        if not a.dead then
            if a.side == "player" then
                alivePlayers += 1
            else
                aliveEnemies += 1
                table.insert(survivors, { unitId = a.unitId, star = a.star, cost = a.cost })
            end
        end
    end

    local outcome: Outcome
    if aliveEnemies == 0 and alivePlayers > 0 then
        outcome = "win"
    elseif alivePlayers == 0 and aliveEnemies > 0 then
        outcome = "loss"
    else
        outcome = "timeout"
    end

    return {
        outcome = outcome,
        ticks = engine.tick,
        events = engine.events,
        survivors = survivors,
        goldStolen = engine.goldStolen,
        playerTraits = engine.playerTraits,
        enemyTraits = engine.enemyTraits,
    }
end

return CombatEngine
