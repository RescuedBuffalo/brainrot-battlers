--!strict
-- Declarative moment definitions. Each entry is keyed by the moment name
-- (matches ability ID so MomentService can look it up from a CombatEvent's
-- source unitId). A moment defines which layers fire, with what intensity,
-- and for how long.
--
-- v1 pass: only capuchino_shadow_leap is fully tuned. Other abilities still
-- render via the existing CombatRenderer path and do NOT fire moments --
-- opting in requires a real entry here.

local MomentDefinitions = {}

export type LayerName =
    "cameraPunch" | "timeDilation" | "vignette" | "hitStop"
    | "particleBurst" | "bigNumber" | "screenShake" | "vo"

export type Layer = {
    [string]: any,
}

export type MomentDef = {
    [LayerName]: Layer,
}

-- Rarity/trait-themed colors we reuse.
local OHIO_PURPLE = Color3.fromRGB(160, 60, 220)
local CAPUCHINO_BLOOD = Color3.fromRGB(200, 20, 50)

-- Keyed by unitId (each unit has exactly one ability in this game).
MomentDefinitions.MOMENTS = {
    capuchino = {
        cameraPunch   = { intensity = 0.6, durationMs = 240, direction = Vector3.new(0, -1, 0.5) },
        timeDilation  = { factor = 0.35, durationMs = 320 },
        vignette      = { color = CAPUCHINO_BLOOD, alpha = 0.55, durationMs = 360 },
        hitStop       = { targetMs = 110 },
        particleBurst = { template = "ShadowLeap", count = 45, color = CAPUCHINO_BLOOD },
        bigNumber     = { scale = 2.2, color = CAPUCHINO_BLOOD },
        screenShake   = { intensity = 0.7, durationMs = 220 },
        vo            = { name = "capuchino_leap", volume = 1.0 },
    },

    -- Placeholder for ohio Reality Collapse -- stubbed here so other
    -- developers can test, but not in v1 showcase scope.
    ohio = {
        cameraPunch   = { intensity = 1.0, durationMs = 220, direction = Vector3.new(0, -1.5, 0) },
        timeDilation  = { factor = 0.35, durationMs = 280 },
        vignette      = { color = OHIO_PURPLE, alpha = 0.55, durationMs = 320 },
        hitStop       = { targetMs = 90 },
        particleBurst = { template = "OhioCollapse", count = 60, color = OHIO_PURPLE },
        bigNumber     = { scale = 1.8, color = OHIO_PURPLE },
        screenShake   = { intensity = 0.9, durationMs = 240 },
        vo            = { name = "ohio_collapse", volume = 1.0 },
    },
}

return MomentDefinitions
