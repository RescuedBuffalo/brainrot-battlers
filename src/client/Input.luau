--!strict
-- Tile-click wiring for the battle arena. Each player-side tile gets a
-- ClickDetector at Init time; clicks are forwarded to UIController.OnTileClick
-- which decides whether to place, move, or select based on current UI state.
--
-- Only player tiles (y in PLAYER_ROWS) are clickable for placement. Enemy
-- tiles are click-through in shop phase. During combat the click-handlers
-- still exist but UIController gates by phase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))

local Input = {}

local uiController: any = nil

local function attachTileClick(tile: BasePart)
    if tile:FindFirstChildOfClass("ClickDetector") then return end
    local cd = Instance.new("ClickDetector")
    cd.MaxActivationDistance = 64
    cd.Parent = tile
    cd.MouseClick:Connect(function()
        local x = tile:GetAttribute("TileX")
        local y = tile:GetAttribute("TileY")
        if typeof(x) == "number" and typeof(y) == "number" then
            if uiController and uiController.OnTileClick then
                uiController.OnTileClick(x, y)
            end
        end
    end)
end

local function attachAll()
    local arena = Workspace:FindFirstChild("BattleArena")
    if not arena then return end
    local tiles = arena:FindFirstChild("Tiles")
    if not tiles then return end
    for _, t in ipairs(tiles:GetChildren()) do
        if t:IsA("BasePart") then
            attachTileClick(t)
        end
    end
end

function Input.Init(deps)
    uiController = deps.UIController

    -- Arena may not exist yet on early client boot (replication). Watch for it.
    attachAll()

    local function onWorkspaceChild(child: Instance)
        if child.Name == "BattleArena" then
            task.wait(0.2)
            attachAll()
        end
    end
    Workspace.ChildAdded:Connect(onWorkspaceChild)

    local arena = Workspace:FindFirstChild("BattleArena")
    if arena then
        local tiles = arena:FindFirstChild("Tiles")
        if tiles then
            tiles.ChildAdded:Connect(function(c)
                if c:IsA("BasePart") then attachTileClick(c) end
            end)
        end
    end
end

return Input
