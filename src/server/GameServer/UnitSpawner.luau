--!strict
-- Spawns / despawns unit models on the battle arena grid.
--   Tile_X_Y world position: (x * TILE_W + ORIGIN_X, TILE_H/2, y * TILE_D + ORIGIN_Z)
-- Spawned unit's HRP centers over the tile with feet resting on the tile top.
-- Rarity is indicated via Highlight outline + optional particle for high tiers.
-- Star level (1..3) shown as yellow badges above the head.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local RarityDefinitions = require(sharedFolder:WaitForChild("RarityDefinitions"))

local templatesFolder = ReplicatedStorage:WaitForChild("UnitTemplates")

local UnitSpawner = {}

local TILE_W = 4
local TILE_D = 4
local TILE_H = 0.4
local COLS = 6
local ROWS = 6
local ORIGIN_X = -(COLS * TILE_W) / 2 + TILE_W / 2
local ORIGIN_Z = -(ROWS * TILE_D) / 2 + TILE_D / 2

-- Template HRPs are built with center at y=0.5 (feet at y=0). When placed on a
-- tile, feet should rest on the tile top (y=TILE_H), so HRP center goes to
-- TILE_H + 0.5.
local PIVOT_LIFT = 0.5

function UnitSpawner.TileToWorld(x: number, y: number): Vector3
    return Vector3.new(
        ORIGIN_X + x * TILE_W,
        TILE_H + PIVOT_LIFT,
        ORIGIN_Z + y * TILE_D
    )
end

function UnitSpawner.WorldToTile(pos: Vector3): (number, number)
    local x = math.round((pos.X - ORIGIN_X) / TILE_W)
    local y = math.round((pos.Z - ORIGIN_Z) / TILE_D)
    return math.clamp(x, 0, COLS - 1), math.clamp(y, 0, ROWS - 1)
end

local function applyRarity(model: Model, rarity: string)
    local def = RarityDefinitions[rarity]
    if not def then return end

    local hl = Instance.new("Highlight")
    hl.Name = "RarityOutline"
    hl.FillTransparency = 1
    hl.OutlineColor = def.color
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = model

    -- Legendary+ gets a glowing halo ring and upward particle stream.
    if rarity == "legendary" or rarity == "mythic" then
        local head = model:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            local attach = head:FindFirstChild("BillboardAnchor") :: Attachment?
            if attach then
                local pe = Instance.new("ParticleEmitter")
                pe.Name = "RarityAura"
                pe.Rate = rarity == "mythic" and 12 or 6
                pe.Lifetime = NumberRange.new(1.2)
                pe.Speed = NumberRange.new(1)
                pe.Size = NumberSequence.new(0.4)
                pe.Color = ColorSequence.new(def.color)
                pe.LightEmission = 0.6
                pe.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.2),
                    NumberSequenceKeypoint.new(1, 1),
                })
                pe.Parent = attach
            end
        end
    end
end

local function applyStarBadges(model: Model, star: number)
    local head = model:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then return end
    if star < 1 then return end

    local badgeFolder = Instance.new("Model")
    badgeFolder.Name = "StarBadges"
    badgeFolder.Parent = model

    local spacing = 0.45
    local startOffset = -((star - 1) * spacing) / 2
    for i = 1, star do
        local s = Instance.new("Part")
        s.Name = "Star" .. i
        s.Size = Vector3.new(0.3, 0.3, 0.3)
        s.Shape = Enum.PartType.Ball
        s.Color = star == 3 and Color3.fromRGB(255, 80, 200) or Color3.fromRGB(255, 215, 0)
        s.Material = Enum.Material.Neon
        s.Anchored = true
        s.CanCollide = false
        s.CanQuery = false
        s.CanTouch = false
        s.Massless = true
        s.Position = head.Position
            + Vector3.new(startOffset + (i - 1) * spacing, head.Size.Y / 2 + 0.6, 0)
        s.Parent = badgeFolder
    end
end

function UnitSpawner.Init(_deps)
end

function UnitSpawner.Spawn(
    unitId: string,
    star: number,
    rarity: string,
    x: number,
    y: number,
    side: string
): Model?
    local template = templatesFolder:FindFirstChild(unitId)
    if not template or not template:IsA("Model") then
        warn("[UnitSpawner] missing template: " .. tostring(unitId))
        return nil
    end

    local model = template:Clone()
    local pos = UnitSpawner.TileToWorld(x, y)
    -- Enemies face player side (-z direction in our layout); players face +z.
    local yaw = side == "enemy" and math.pi or 0
    model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))

    applyRarity(model, rarity)
    applyStarBadges(model, star)

    -- Runtime attributes for client-side reactive display and server-side lookups.
    model:SetAttribute("UnitId", unitId)
    model:SetAttribute("Star", star)
    model:SetAttribute("Rarity", rarity)
    model:SetAttribute("Side", side)
    model:SetAttribute("TileX", x)
    model:SetAttribute("TileY", y)

    local arena = workspace:WaitForChild("BattleArena")
    local sideFolderName = side == "player" and "PlayerSide" or "EnemySide"
    local sideFolder = arena:WaitForChild(sideFolderName)
    model.Parent = sideFolder
    return model
end

function UnitSpawner.Despawn(model: Model?)
    if model and model.Parent then
        model:Destroy()
    end
end

function UnitSpawner.ClearAll()
    local arena = workspace:FindFirstChild("BattleArena")
    if not arena then return end
    for _, folderName in ipairs({"PlayerSide", "EnemySide"}) do
        local f = arena:FindFirstChild(folderName)
        if f then
            for _, child in ipairs(f:GetChildren()) do
                child:Destroy()
            end
        end
    end
end

return UnitSpawner
