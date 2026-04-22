--!strict
-- Populates the lobby pedestals with the player's collection state. Each
-- pedestal is a named Part with a UnitId attribute set by BootstrapInstances.
-- RefreshPedestals clones the unit template onto each pedestal, tinting by
-- the owned rarity (or greyed out if not owned).
--
-- Single-server-per-player MVP: one global lobby, refreshed on player join
-- and after every collection mutation (crate open). For multi-player
-- sharing we'd want per-player lobbies or a PlayerGui-driven showcase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LobbyService = {}

local UnitDefinitions
local RarityDefinitions
local templatesFolder: Folder

local function clearPedestalModels(pedestal: Instance)
    for _, c in ipairs(pedestal:GetChildren()) do
        if c:IsA("Model") then c:Destroy() end
    end
end

local function buildDisplay(pedestal: BasePart, unitId: string, rarity: string?)
    local template = templatesFolder:FindFirstChild(unitId)
    if not template or not template:IsA("Model") then return end

    local model = template:Clone()
    local pedTop = pedestal.Position.Y + pedestal.Size.Y * 0.5
    -- Template HRP is at y=0.5 (feet at 0). Place feet on pedestal top.
    model:PivotTo(CFrame.new(pedestal.Position.X, pedTop + 0.5, pedestal.Position.Z))

    local owned = rarity ~= nil
    if owned then
        local rDef = RarityDefinitions[rarity :: string]
        if rDef then
            local hl = Instance.new("Highlight")
            hl.Name = "LobbyOutline"
            hl.FillTransparency = 1
            hl.OutlineColor = rDef.color
            hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = model

            -- Rarity-colored label above head
            local head = model:FindFirstChild("Head")
            if head and head:IsA("BasePart") then
                local bb = Instance.new("BillboardGui")
                bb.Name = "RarityLabel"
                bb.Size = UDim2.fromOffset(140, 36)
                bb.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
                bb.AlwaysOnTop = true
                bb.Parent = head
                local label = Instance.new("TextLabel")
                label.Size = UDim2.fromScale(1, 1)
                label.BackgroundTransparency = 1
                label.Text = (rarity :: string):upper()
                label.TextColor3 = rDef.color
                label.TextStrokeColor3 = Color3.new(0, 0, 0)
                label.TextStrokeTransparency = 0
                label.Font = Enum.Font.GothamBlack
                label.TextScaled = true
                label.Parent = bb
            end

            -- Mythic gets a floating particle aura
            if rarity == "mythic" then
                local head2 = model:FindFirstChild("Head")
                if head2 and head2:IsA("BasePart") then
                    local attach = head2:FindFirstChild("BillboardAnchor") :: Attachment?
                    if attach then
                        local pe = Instance.new("ParticleEmitter")
                        pe.Name = "LobbyAura"
                        pe.Rate = 10
                        pe.Lifetime = NumberRange.new(1.5)
                        pe.Speed = NumberRange.new(1.5)
                        pe.Size = NumberSequence.new(0.5)
                        pe.Color = ColorSequence.new(rDef.color)
                        pe.LightEmission = 0.7
                        pe.Transparency = NumberSequence.new({
                            NumberSequenceKeypoint.new(0, 0.2),
                            NumberSequenceKeypoint.new(1, 1),
                        })
                        pe.Parent = attach
                    end
                end
            end
        end
    else
        -- Not owned: dim the display
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Transparency = 0.6
            end
        end
        local head = model:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            local bb = Instance.new("BillboardGui")
            bb.Name = "LockedLabel"
            bb.Size = UDim2.fromOffset(120, 30)
            bb.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
            bb.AlwaysOnTop = true
            bb.Parent = head
            local label = Instance.new("TextLabel")
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.Text = "🔒 LOCKED"
            label.TextColor3 = Color3.fromRGB(180, 180, 200)
            label.TextStrokeColor3 = Color3.new(0, 0, 0)
            label.TextStrokeTransparency = 0
            label.Font = Enum.Font.GothamBold
            label.TextScaled = true
            label.Parent = bb
        end
    end

    model.Parent = pedestal
end

function LobbyService.Init(deps)
    local shared = deps.Shared
    UnitDefinitions = require(shared:WaitForChild("UnitDefinitions"))
    RarityDefinitions = require(shared:WaitForChild("RarityDefinitions"))
    templatesFolder = ReplicatedStorage:WaitForChild("UnitTemplates")
end

function LobbyService.RefreshPedestals(collection: { [string]: string }?)
    if not templatesFolder then return end
    local lobby = Workspace:FindFirstChild("LobbyHub")
    if not lobby then return end
    local pedestals = lobby:FindFirstChild("Pedestals")
    if not pedestals then return end

    collection = collection or {}
    for _, pedestal in ipairs(pedestals:GetChildren()) do
        if pedestal:IsA("BasePart") then
            local unitId = pedestal:GetAttribute("UnitId")
            if unitId and UnitDefinitions[unitId] then
                clearPedestalModels(pedestal)
                buildDisplay(pedestal, unitId, (collection :: any)[unitId])
            end
        end
    end
end

return LobbyService
