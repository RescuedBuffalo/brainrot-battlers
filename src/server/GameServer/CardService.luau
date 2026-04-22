--!strict
-- Applies card effects to a PlayerState. Cards declare an effect.kind in
-- their definition; this module has a small dispatch table per kind.
--
-- Cards come in two scopes:
--   "run"           -> effect lives on state.activeCards for the rest of the
--                       run, consumed by CombatEngine hooks when relevant
--   "next_combat"   -> applied at the start of the next combat, discarded
--                       after that combat resolves
--
-- CardService never talks to the client directly -- GameManager wraps it and
-- broadcasts state afterward.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardService = {}

local CardDefinitions
local ShopService  -- needed for applyActivation on free reroll mod

local APPLIERS: { [string]: (state: any, card: any, payload: any) -> (boolean, string?) } = {}

-- ---------- effect handlers ---------- --

-- Tung Tung's Nap: pick a unit (bench or board), +200 max HP for the rest of
-- the run, cost -3 gold. Effect is stored as an ActiveCard on the state so
-- CombatEngine can see it through GameManager's pre-combat prep.
APPLIERS.unit_hp_bonus = function(state, card, payload)
    if state.gold < math.abs(card.effect.gold) then
        return false, "insufficient gold"
    end
    if not payload or not payload.targetUnitInstanceId then
        return false, "missing target"
    end
    -- targetUnitInstanceId is a hash we generate below: "bench:IDX" or "board:IDX"
    state.gold += card.effect.gold
    table.insert(state.activeCards, {
        id = card.id,
        scope = card.scope,
        payload = {
            targetUnitInstanceId = payload.targetUnitInstanceId,
            amount = card.effect.amount,
        },
    })
    return true
end

APPLIERS.trait_as_bonus = function(state, card, payload)
    table.insert(state.activeCards, {
        id = card.id,
        scope = card.scope,
        payload = {
            trait = card.effect.trait,
            bonus = card.effect.bonus,
            benchPenalty = card.effect.benchPenalty,
        },
    })
    return true
end

APPLIERS.portal = function(state, card, payload)
    table.insert(state.activeCards, {
        id = card.id,
        scope = card.scope,
        payload = {
            freeReroll = card.effect.freeReroll,
            extraEnemies = card.effect.extraEnemies,
        },
    })
    return true
end

-- Forge cards: all just push an ActiveCard and let CombatEngine hooks read
-- state.activeCards. CardService doesn't need to know the details.
APPLIERS.trait_threshold_mod = function(state, card)
    table.insert(state.activeCards, {
        id = card.id, scope = card.scope,
        payload = { trait = card.effect.trait, reduction = card.effect.reduction },
    })
    return true
end

APPLIERS.trait_ad_per_win = function(state, card)
    table.insert(state.activeCards, {
        id = card.id, scope = card.scope,
        payload = {
            trait = card.effect.trait,
            perWin = card.effect.perWin,
            cap = card.effect.cap,
        },
    })
    return true
end

APPLIERS.trait_cast_mana_share = function(state, card)
    -- Supports both sourceTrait (legacy) and sourceUnitId (spec-correct for
    -- tralalero_surge). CombatEngine's hook reads whichever is present.
    table.insert(state.activeCards, {
        id = card.id, scope = card.scope,
        payload = {
            sourceTrait = card.effect.sourceTrait,
            sourceUnitId = card.effect.sourceUnitId,
            allyTrait = card.effect.allyTrait,
            amount = card.effect.amount,
        },
    })
    return true
end

-- ---------- public API ---------- --

function CardService.Init(deps)
    local shared = deps.Shared
    CardDefinitions = require(shared:WaitForChild("CardDefinitions"))
    ShopService = deps.ShopService
end

function CardService.Apply(state, cardId: string, payload: any?): (boolean, string?)
    if not CardDefinitions then return false, "not initialized" end
    local card = CardDefinitions.CARDS[cardId]
    if not card then return false, "unknown card " .. tostring(cardId) end

    local applier = APPLIERS[card.effect.kind]
    if not applier then
        return false, "unknown effect kind " .. tostring(card.effect.kind)
    end

    return applier(state, card, payload or {})
end

-- Called by GameManager before a combat starts. Returns a combat-mods table
-- that spawnCombatVisuals / CombatEngine.Resolve can read to apply the
-- appropriate tweaks (bench penalty, extra enemies, AS buffs, etc.).
function CardService.BuildCombatMods(state): any
    local mods = {
        benchPenalty = 0,
        extraEnemies = 0,
        traitAsBonus = {},       -- { [trait] = bonusPct }
        traitThresholdReduction = {}, -- { [trait] = amount }
        traitAdBonus = {},       -- { [trait] = bonus }
        manaShare = nil,         -- { sourceTrait, allyTrait, amount }
        unitHpBonuses = {},      -- { [instanceId] = amount }
    }

    for _, active in ipairs(state.activeCards or {}) do
        local p = active.payload or {}
        if active.id == "tungtung_nap" then
            mods.unitHpBonuses[p.targetUnitInstanceId] = (mods.unitHpBonuses[p.targetUnitInstanceId] or 0) + (p.amount or 0)
        elseif active.id == "espresso_spill" then
            mods.benchPenalty += (p.benchPenalty or 0)
            mods.traitAsBonus[p.trait] = (mods.traitAsBonus[p.trait] or 0) + (p.bonus or 0)
        elseif active.id == "skibidi_portal" then
            mods.extraEnemies += (p.extraEnemies or 0)
            -- freeReroll handled by ShopService in the next shop phase
        elseif active.id == "ohio_energy" then
            mods.traitThresholdReduction[p.trait] = (mods.traitThresholdReduction[p.trait] or 0) + (p.reduction or 0)
        elseif active.id == "sigma_grindset" then
            local stacks = state.combatsWon or 0
            local bonus = math.min(p.cap or 0.5, stacks * (p.perWin or 0))
            mods.traitAdBonus[p.trait] = (mods.traitAdBonus[p.trait] or 0) + bonus
        elseif active.id == "tralalero_surge" then
            mods.manaShare = {
                sourceTrait = p.sourceTrait,
                sourceUnitId = p.sourceUnitId,
                allyTrait = p.allyTrait,
                amount = p.amount,
            }
        end
    end

    return mods
end

-- Expire next_combat-scope cards after a combat finishes.
function CardService.ExpireNextCombatCards(state)
    local kept = {}
    for _, c in ipairs(state.activeCards or {}) do
        if c.scope ~= "next_combat" then
            table.insert(kept, c)
        end
    end
    state.activeCards = kept
end

-- Phase 12 spec P0-3: Skibidi Portal grants UNLIMITED free rerolls for the
-- next shop visit (not just one). GameManager reads HasFreeRerollFlag when
-- entering a shop phase, and calls ClearFreeRerollFlag when the visit ends
-- (combat start from pre-combat shop, or HandleContinue from shop node).

function CardService.HasFreeRerollFlag(state): boolean
    for _, c in ipairs(state.activeCards or {}) do
        if c.id == "skibidi_portal" and c.payload and c.payload.freeReroll then
            return true
        end
    end
    return false
end

function CardService.ClearFreeRerollFlag(state)
    local kept = {}
    for _, c in ipairs(state.activeCards or {}) do
        if c.id == "skibidi_portal" then
            if c.payload then c.payload.freeReroll = false end
            -- If the extraEnemies half has already fired (next_combat scope
            -- drops through ExpireNextCombatCards), the card gets garbage-
            -- collected naturally. Here we just clear the freeReroll half;
            -- the card stays on activeCards if extraEnemies is still pending.
            local stillLive = c.payload and c.payload.extraEnemies and c.payload.extraEnemies > 0
            if stillLive then
                table.insert(kept, c)
            end
        else
            table.insert(kept, c)
        end
    end
    state.activeCards = kept
end

-- Backward-compat alias for the former one-shot consumer; now equivalent to
-- HasFreeRerollFlag since the visit-wide flag is the single source of truth.
function CardService.ConsumeFreeReroll(state): boolean
    return CardService.HasFreeRerollFlag(state)
end

return CardService
