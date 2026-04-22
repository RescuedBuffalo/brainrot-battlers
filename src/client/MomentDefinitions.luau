--!strict
-- Declarative moment definitions. Keyed by "<unitId>_<abilitySlug>" where
-- abilitySlug is the UnitDefinitions abilityName lowercased with spaces
-- replaced by underscores (e.g. "Shadow Leap" -> "shadow_leap"). Only
-- abilities with an entry here trigger a Moment; all others fall through
-- to the normal CombatRenderer path.

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

-- v1: only capuchino_shadow_leap is fully tuned per spec Appendix B. Other
-- abilities intentionally have no moment entry -- they render through the
-- existing ability flash + shoot/aoe/dmg pipeline untouched.
--
-- Values below are the spec's Appendix B literals. Iterate them during
-- playtesting (Phase 12 step 11 in the roadmap) if the feel needs adjustment.
MomentDefinitions.MOMENTS = {
    capuchino_shadow_leap = {
        cameraPunch = {
            direction = Vector3.new(0, 0, -1),
            intensity = 0.8,
            durationMs = 200,
        },
        timeDilation = {
            factor = 0.35,
            durationMs = 280,
        },
        vignette = {
            color = Color3.fromRGB(180, 40, 60),   -- blood-red, shadow-assassin
            alpha = 0.55,
            durationMs = 320,
        },
        hitStop = {
            targetMs = 90,
        },
        particleBurst = {
            template = "ShadowLeapImpact",          -- placeholder
            count = 60,
            color = Color3.fromRGB(240, 50, 80),
        },
        bigNumber = {
            scale = 1.7,
            color = Color3.fromRGB(240, 50, 80),
        },
        screenShake = {
            intensity = 0.7,
            durationMs = 180,
        },
        vo = {
            name = "capuchino_leap",                -- VO_REGISTRY lookup key
            volume = 1.0,
        },
    },
}

return MomentDefinitions
