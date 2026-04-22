--!strict
-- Event + Forge cards. Each card declares its kind (event / forge), its
-- display copy, and a machine-readable effect descriptor that CardService
-- dispatches on.
--
-- v1 pool is deliberately tiny (3 events + 3 forges) -- enough to feel
-- different across 3 runs, small enough to fully tune.

local CardDefinitions = {}

export type CardKind = "event" | "forge"
export type CardScope = "next_combat" | "run"
export type CardEffect = {
    kind: string,         -- dispatch key (see CardService.applyEffect)
    [string]: any,
}
export type Card = {
    id: string,
    kind: CardKind,
    name: string,
    emoji: string,
    desc: string,
    cost: string?,        -- human-readable cost display ("-3 gold", "-1 bench slot", etc.)
    effect: CardEffect,
    scope: CardScope,     -- when the effect expires
    needsUnitTarget: boolean?,  -- client prompts for a unit pick (Tung Tung's Nap)
}

CardDefinitions.CARDS = {
    -- Event cards
    tungtung_nap = {
        id = "tungtung_nap",
        kind = "event",
        name = "Tung Tung's Nap",
        emoji = "😴",
        desc = "Pick one unit: +200 max HP for the run. Cost: -3 gold.",
        cost = "-3 gold",
        effect = { kind = "unit_hp_bonus", amount = 200, gold = -3 },
        scope = "run",
        needsUnitTarget = true,
    },
    espresso_spill = {
        id = "espresso_spill",
        kind = "event",
        name = "Espresso Spill",
        emoji = "☕",
        desc = "Italian units +20% attack speed next combat. Cost: -1 bench slot next combat.",
        cost = "-1 bench slot",
        effect = { kind = "trait_as_bonus", trait = "italian", bonus = 0.20, benchPenalty = 1 },
        scope = "next_combat",
    },
    skibidi_portal = {
        id = "skibidi_portal",
        kind = "event",
        name = "Skibidi Toilet Portal",
        emoji = "🚽",
        desc = "Next shop free reroll + 1 extra enemy next combat.",
        effect = { kind = "portal", freeReroll = true, extraEnemies = 1 },
        scope = "next_combat",
    },

    -- Forge cards (persist run-long)
    ohio_energy = {
        id = "ohio_energy",
        kind = "forge",
        name = "Ohio Energy",
        emoji = "🌀",
        desc = "Ohio trait thresholds reduced by 1 (2 Ohio activates tier 1).",
        effect = { kind = "trait_threshold_mod", trait = "ohio", reduction = 1 },
        scope = "run",
    },
    sigma_grindset = {
        id = "sigma_grindset",
        kind = "forge",
        name = "Sigma Grindset",
        emoji = "💪",
        desc = "Sigma units gain +5% AD per Combat won (compounds, capped +50%).",
        effect = { kind = "trait_ad_per_win", trait = "sigma", perWin = 0.05, cap = 0.50 },
        scope = "run",
    },
    tralalero_surge = {
        id = "tralalero_surge",
        kind = "forge",
        name = "Tralalero Surge",
        emoji = "🦈",
        desc = "When a Tralalero-trait unit casts, allied Italians gain 20 mana.",
        effect = { kind = "trait_cast_mana_share", sourceTrait = "italian", allyTrait = "italian", amount = 20 },
        scope = "run",
    },
}

-- Ordered lists for the draft picker; ensures a stable UI order regardless
-- of table iteration.
CardDefinitions.EVENT_ORDER = { "tungtung_nap", "espresso_spill", "skibidi_portal" }
CardDefinitions.FORGE_ORDER = { "ohio_energy", "sigma_grindset", "tralalero_surge" }

-- Returns a list of up to `count` card ids of the given kind, sampled
-- without repetition. Deterministic given the provided rng.
function CardDefinitions.sample(kind: CardKind, count: number, rng: () -> number): { string }
    local source
    if kind == "event" then source = CardDefinitions.EVENT_ORDER
    elseif kind == "forge" then source = CardDefinitions.FORGE_ORDER
    else return {} end

    local pool = {}
    for _, id in ipairs(source) do table.insert(pool, id) end

    local out = {}
    while #out < count and #pool > 0 do
        local idx = math.floor(rng() * #pool) + 1
        idx = math.max(1, math.min(#pool, idx))
        table.insert(out, table.remove(pool, idx))
    end
    return out
end

return CardDefinitions
