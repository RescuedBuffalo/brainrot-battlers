--!strict
-- Rarity table. weight is for uniform global rarity roll (unused by CrateService,
-- which has its own per-crate tables, but kept for reference).

return {
    common    = { name="Common",    statMult=1.00, color=Color3.fromHex("#9ca3af"), weight=650 },
    rare      = { name="Rare",      statMult=1.05, color=Color3.fromHex("#3b82f6"), weight=220 },
    epic      = { name="Epic",      statMult=1.12, color=Color3.fromHex("#a855f7"), weight=95  },
    legendary = { name="Legendary", statMult=1.20, color=Color3.fromHex("#f59e0b"), weight=30  },
    mythic    = { name="Mythic",    statMult=1.30, color=Color3.fromHex("#ec4899"), weight=5   },
}
