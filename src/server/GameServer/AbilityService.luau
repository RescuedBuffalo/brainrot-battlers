--!strict
-- Per-ability resolvers. Each handler receives (engine, caster) and mutates
-- engine state directly. Helpers (dealDamage, findLowestHp, etc.) are
-- accessed via engine.helpers -- attached by CombatEngine -- so this module
-- never imports CombatEngine and stays free of cyclic requires.
--
-- Ability damage formulas multiply by caster.abilityMult (mage trait bumps
-- this to 1.3 for mages). Abilities do NOT grant mana on self-hit.

local AbilityService = {}

type Handler = (engine: any, caster: any) -> ()

local handlers: { [string]: Handler } = {}

local function collectIds(actors)
    local ids = {}
    for _, a in ipairs(actors) do table.insert(ids, a.id) end
    return ids
end

local function registerAll()
    -- skibidi: Flush Strike -- teleport behind lowest HP, 180% AD
    handlers.skibidi = function(engine, actor)
        local target = engine.helpers.findLowestHp(engine, actor)
        if not target then return end
        engine.helpers.teleportBehind(engine, actor, target)
        local dmg = actor.atk * 1.8 * actor.abilityMult
        engine.helpers.dealDamage(engine, actor, target, dmg, true)
    end

    -- sigma: Gigachad Slam -- closest enemy, 220% AD + stun 5 ticks
    handlers.sigma = function(engine, actor)
        local target = engine.helpers.findClosest(engine, actor)
        if not target then return end
        local dmg = actor.atk * 2.2 * actor.abilityMult
        engine.helpers.dealDamage(engine, actor, target, dmg, true)
        if not target.dead then
            target.stunned = 5
            engine.helpers.emit(engine, {
                kind = "stun",
                source = actor.id,
                target = target.id,
                ticks = 5,
            })
        end
    end

    -- gyatt: Rapid Fire -- 3x 70% AD to lowest HP (re-pick between shots)
    handlers.gyatt = function(engine, actor)
        for _ = 1, 3 do
            local target = engine.helpers.findLowestHp(engine, actor)
            if not target then return end
            local dmg = actor.atk * 0.7 * actor.abilityMult
            engine.helpers.emit(engine, {
                kind = "shoot",
                source = actor.id,
                target = target.id,
                ability = true,
            })
            engine.helpers.dealDamage(engine, actor, target, dmg, false)
        end
    end

    -- tralalero: Triple Chomp -- 3x 80% AD to closest (re-pick between)
    handlers.tralalero = function(engine, actor)
        for _ = 1, 3 do
            local target = engine.helpers.findClosest(engine, actor)
            if not target then return end
            local dmg = actor.atk * 0.8 * actor.abilityMult
            engine.helpers.dealDamage(engine, actor, target, dmg, false)
        end
    end

    -- bombardiro: Carpet Bomb -- 170% AD in 2-tile Chebyshev radius around target
    handlers.bombardiro = function(engine, actor)
        local anchor = engine.helpers.findLowestHp(engine, actor)
        if not anchor then return end
        local hit = {}
        for _, o in ipairs(engine.actorsList) do
            if not o.dead and o.side ~= actor.side and engine.helpers.chebyshev(o, anchor) <= 2 then
                table.insert(hit, o)
            end
        end
        engine.helpers.emit(engine, {
            kind = "aoe",
            source = actor.id,
            center = {anchor.x, anchor.y},
            targets = collectIds(hit),
            radius = 2,
        })
        local dmg = actor.atk * 1.7 * actor.abilityMult
        for _, t in ipairs(hit) do
            engine.helpers.dealDamage(engine, actor, t, dmg, false)
        end
    end

    -- tungtung: Timber Wall -- self +700 shield * abilityMult
    handlers.tungtung = function(engine, actor)
        local amount = 700 * actor.abilityMult
        actor.shield += amount
        engine.helpers.emit(engine, {
            kind = "shield",
            source = actor.id,
            target = actor.id,
            amount = amount,
        })
    end

    -- ballerina: Caffeine Rush -- allies within Chebyshev 2 get +50% AS for 22 ticks
    handlers.ballerina = function(engine, actor)
        local buffed = {}
        for _, o in ipairs(engine.actorsList) do
            if not o.dead and o.side == actor.side and engine.helpers.chebyshev(o, actor) <= 2 then
                o.asBuff = 22
                o.asBuffMult = 1.5
                table.insert(buffed, o)
            end
        end
        engine.helpers.emit(engine, {
            kind = "buff",
            source = actor.id,
            targets = collectIds(buffed),
            buff = "attack_speed",
            amount = 0.5,
            duration = 22,
        })
    end

    -- capuchino: Shadow Leap -- highest cost*star enemy, teleport behind, 320% AD crit
    handlers.capuchino = function(engine, actor)
        local target = engine.helpers.findByScore(engine, actor, function(o)
            return o.cost * o.star
        end)
        if not target then return end
        engine.helpers.teleportBehind(engine, actor, target)
        local dmg = actor.atk * 3.2 * actor.abilityMult
        engine.helpers.dealDamage(engine, actor, target, dmg, true)
    end

    -- fanum: Tax Collection -- closest, 260% AD. +2 gold to engine stash if player.
    handlers.fanum = function(engine, actor)
        local target = engine.helpers.findClosest(engine, actor)
        if not target then return end
        local dmg = actor.atk * 2.6 * actor.abilityMult
        engine.helpers.dealDamage(engine, actor, target, dmg, false)
        if actor.side == "player" then
            engine.goldStolen = (engine.goldStolen or 0) + 2
            engine.helpers.emit(engine, {
                kind = "gold",
                source = actor.id,
                amount = 2,
            })
        end
    end

    -- ohio: Reality Collapse -- 250% AD to ALL enemies
    handlers.ohio = function(engine, actor)
        local all = engine.helpers.enemiesOf(engine, actor)
        engine.helpers.emit(engine, {
            kind = "aoe",
            source = actor.id,
            center = {actor.x, actor.y},
            targets = collectIds(all),
            global = true,
        })
        local dmg = actor.atk * 2.5 * actor.abilityMult
        for _, t in ipairs(all) do
            engine.helpers.dealDamage(engine, actor, t, dmg, false)
        end
    end
end

function AbilityService.Register(unitId: string, handler: Handler)
    handlers[unitId] = handler
end

function AbilityService.Cast(engine: any, caster: any)
    local h = handlers[caster.unitId]
    if not h then return end
    h(engine, caster)
end

function AbilityService.GetRegistered(): { string }
    local ids = {}
    for uid in pairs(handlers) do table.insert(ids, uid) end
    return ids
end

function AbilityService.Init(_deps)
    if next(handlers) == nil then
        registerAll()
    end
end

function AbilityService.InitStandalone()
    if next(handlers) == nil then
        registerAll()
    end
end

return AbilityService
