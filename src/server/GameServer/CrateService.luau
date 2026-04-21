--!strict
-- Crate opening logic. Phase 8 fills this in.

local CrateService = {}

export type CrateTier = "common" | "rare" | "epic" | "legendary"
export type DropResult = {
    unitId: string,
    rarity: string,
    upgraded: boolean,
    goldRefund: number,
}

function CrateService.Init(deps)
end

function CrateService.Open(_userId: number, _tier: CrateTier): DropResult?
    return nil
end

return CrateService
