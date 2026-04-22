--!strict
-- Renders the run map as a toggleable overlay and the node-pick prompt that
-- fires between nodes. Both panels live on MainUI; RunMapController owns
-- construction and update.
--
-- The map overlay is toggled by the "View Map" button in TopHud (UIController
-- exposes the toggle). The node-pick panel auto-opens when state.phase ==
-- "nodeSelect" so the player can choose the next node.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local RunMapController = {}

local player = Players.LocalPlayer
local remotes: Folder

-- Cached refs
local mapOverlay: Frame
local mapCanvas: Frame
local nodeChoicePanel: Frame
local nodeChoiceList: Frame

-- Node type → display config
local NODE_VISUAL = {
    combat = { emoji = "⚔️",  label = "Combat", color = Color3.fromRGB(210, 90, 90)  },
    elite  = { emoji = "👹",  label = "Elite",  color = Color3.fromRGB(200, 60, 180) },
    shop   = { emoji = "🛒",  label = "Shop",   color = Color3.fromRGB(80, 160, 210) },
    event  = { emoji = "❓",  label = "Event",  color = Color3.fromRGB(140, 200, 110) },
    forge  = { emoji = "🔨",  label = "Forge",  color = Color3.fromRGB(220, 160, 60) },
    boss   = { emoji = "☠️",  label = "BOSS",   color = Color3.fromRGB(240, 60, 50)  },
}

-- ---------- layout helpers ---------- --

local function makeCorner(parent: Instance, radius: number?)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = parent
end

local function makeStroke(parent: Instance, color: Color3, thickness: number?)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 2
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

-- ---------- construction ---------- --

local function buildOverlay(parent: ScreenGui)
    mapOverlay = Instance.new("Frame")
    mapOverlay.Name = "RunMapOverlay"
    mapOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
    mapOverlay.Position = UDim2.fromScale(0.5, 0.5)
    mapOverlay.Size = UDim2.new(1, -40, 1, -120)
    mapOverlay.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    mapOverlay.BackgroundTransparency = 0.08
    mapOverlay.BorderSizePixel = 0
    mapOverlay.Visible = false
    mapOverlay.ZIndex = 20
    makeCorner(mapOverlay, 12)
    makeStroke(mapOverlay, Color3.fromRGB(140, 140, 170), 2)
    mapOverlay.Parent = parent

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.fromOffset(0, 8)
    title.BackgroundTransparency = 1
    title.Text = "🗺️ Run Map"
    title.TextColor3 = Color3.fromRGB(255, 220, 120)
    title.Font = Enum.Font.GothamBlack
    title.TextScaled = true
    title.ZIndex = 21
    title.Parent = mapOverlay

    mapCanvas = Instance.new("Frame")
    mapCanvas.Name = "Canvas"
    mapCanvas.AnchorPoint = Vector2.new(0.5, 0)
    mapCanvas.Position = UDim2.new(0.5, 0, 0, 50)
    mapCanvas.Size = UDim2.new(1, -40, 1, -110)
    mapCanvas.BackgroundTransparency = 1
    mapCanvas.ZIndex = 21
    mapCanvas.Parent = mapOverlay

    local closeBtn = Instance.new("TextButton")
    closeBtn.AnchorPoint = Vector2.new(0.5, 1)
    closeBtn.Position = UDim2.new(0.5, 0, 1, -10)
    closeBtn.Size = UDim2.fromOffset(180, 40)
    closeBtn.BackgroundColor3 = Color3.fromRGB(80, 120, 180)
    closeBtn.Text = "Close"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextScaled = true
    closeBtn.BorderSizePixel = 0
    closeBtn.ZIndex = 22
    makeCorner(closeBtn, 8)
    closeBtn.MouseButton1Click:Connect(function() mapOverlay.Visible = false end)
    closeBtn.Parent = mapOverlay
end

local function buildNodeChoicePanel(parent: ScreenGui)
    nodeChoicePanel = Instance.new("Frame")
    nodeChoicePanel.Name = "NodeChoicePanel"
    nodeChoicePanel.AnchorPoint = Vector2.new(0.5, 0.5)
    nodeChoicePanel.Position = UDim2.fromScale(0.5, 0.5)
    nodeChoicePanel.Size = UDim2.fromOffset(520, 320)
    nodeChoicePanel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    nodeChoicePanel.BorderSizePixel = 0
    nodeChoicePanel.Visible = false
    nodeChoicePanel.ZIndex = 15
    makeCorner(nodeChoicePanel, 12)
    makeStroke(nodeChoicePanel, Color3.fromRGB(180, 180, 210), 2)
    nodeChoicePanel.Parent = parent

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 36)
    title.Position = UDim2.fromOffset(10, 12)
    title.BackgroundTransparency = 1
    title.Text = "Pick your next node"
    title.TextColor3 = Color3.fromRGB(255, 220, 120)
    title.Font = Enum.Font.GothamBlack
    title.TextScaled = true
    title.ZIndex = 16
    title.Parent = nodeChoicePanel

    nodeChoiceList = Instance.new("Frame")
    nodeChoiceList.Name = "Options"
    nodeChoiceList.AnchorPoint = Vector2.new(0.5, 0)
    nodeChoiceList.Position = UDim2.new(0.5, 0, 0, 60)
    nodeChoiceList.Size = UDim2.new(1, -40, 1, -80)
    nodeChoiceList.BackgroundTransparency = 1
    nodeChoiceList.ZIndex = 16
    nodeChoiceList.Parent = nodeChoicePanel

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 12)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = nodeChoiceList
end

-- ---------- rendering ---------- --

local function clearChildren(f: Instance)
    for _, c in ipairs(f:GetChildren()) do
        if not c:IsA("UILayout") then c:Destroy() end
    end
end

local function renderMap(state: any)
    if not mapCanvas or not state or not state.runMap then return end
    clearChildren(mapCanvas)

    local map = state.runMap
    local layerCount = map.layerCount or 9

    -- Layout: grid columns = max width found across layers, rows = layerCount.
    -- Walk layers bottom-up so layer 1 (start) is at the bottom of the canvas
    -- and Boss is at the top.
    local maxWidth = 1
    local byLayer: { [number]: { any } } = {}
    for _, node in pairs(map.nodes) do
        byLayer[node.layer] = byLayer[node.layer] or {}
        table.insert(byLayer[node.layer], node)
    end
    for _, nodes in pairs(byLayer) do
        if #nodes > maxWidth then maxWidth = #nodes end
        table.sort(nodes, function(a, b) return a.column < b.column end)
    end

    local cellW = 1 / maxWidth
    local cellH = 1 / layerCount

    -- Build a map nodeId -> AbsolutePosition for edge drawing (approx via UDim2).
    -- We'll draw nodes first then edges as Frames between them. For v1 we'll
    -- skip physical lines and just rely on layer-by-layer visual grouping --
    -- good enough to communicate "row of options".

    for layer = 1, layerCount do
        local nodes = byLayer[layer] or {}
        local count = #nodes
        for i, node in ipairs(nodes) do
            local vis = NODE_VISUAL[node.type] or NODE_VISUAL.combat
            local btn = Instance.new("TextButton")
            btn.Name = node.id
            btn.Size = UDim2.new(0, 80, 0, 48)
            -- Center the column in the row
            local xFrac = (i - 0.5) / math.max(1, count)
            local yFrac = 1 - ((layer - 0.5) / layerCount)
            btn.Position = UDim2.new(xFrac, -40, yFrac, -24)
            btn.BackgroundColor3 = vis.color
            btn.BackgroundTransparency = node.visited and 0.6 or 0.15
            btn.BorderSizePixel = 0
            btn.Text = ("%s\n%s"):format(vis.emoji, vis.label)
            btn.TextColor3 = Color3.new(1, 1, 1)
            btn.TextScaled = true
            btn.Font = Enum.Font.GothamBold
            btn.ZIndex = 22
            makeCorner(btn, 6)
            if node.id == state.currentNodeId then
                makeStroke(btn, Color3.fromRGB(255, 230, 120), 3)
            elseif node.visited then
                makeStroke(btn, Color3.fromRGB(100, 100, 110), 1)
            else
                makeStroke(btn, Color3.fromRGB(80, 80, 100), 1)
            end
            btn.Parent = mapCanvas
        end
    end
end

local function renderNodeChoice(state: any)
    if not nodeChoiceList then return end
    clearChildren(nodeChoiceList)

    if state.phase ~= "nodeSelect" or not state.runMap or not state.currentNodeId then
        nodeChoicePanel.Visible = false
        return
    end

    local current = state.runMap.nodes[state.currentNodeId]
    if not current or not current.nextNodeIds or #current.nextNodeIds == 0 then
        nodeChoicePanel.Visible = false
        return
    end

    nodeChoicePanel.Visible = true

    for i, nextId in ipairs(current.nextNodeIds) do
        local node = state.runMap.nodes[nextId]
        if not node then continue end
        local vis = NODE_VISUAL[node.type] or NODE_VISUAL.combat

        local btn = Instance.new("TextButton")
        btn.Name = nextId
        btn.Size = UDim2.fromOffset(140, 180)
        btn.BackgroundColor3 = vis.color
        btn.BorderSizePixel = 0
        btn.BackgroundTransparency = 0.08
        btn.Text = ("%s\n%s"):format(vis.emoji, vis.label)
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.GothamBlack
        btn.TextScaled = true
        btn.ZIndex = 17
        btn.LayoutOrder = i
        makeCorner(btn, 10)
        makeStroke(btn, Color3.fromRGB(255, 230, 120), 2)
        btn.MouseButton1Click:Connect(function()
            remotes.SelectNextNode:FireServer({ nodeId = nextId })
        end)
        btn.Parent = nodeChoiceList
    end
end

-- ---------- public API ---------- --

function RunMapController.Init(deps)
    remotes = deps.Remotes
    local pg = player:WaitForChild("PlayerGui")
    local mainUI = pg:WaitForChild("MainUI", 5)
    if not mainUI then
        warn("[RunMapController] MainUI not found")
        return
    end
    buildOverlay(mainUI)
    buildNodeChoicePanel(mainUI)
end

function RunMapController.ToggleMap()
    if mapOverlay then
        mapOverlay.Visible = not mapOverlay.Visible
    end
end

function RunMapController.Render(state: any)
    if not state then return end
    if mapOverlay and mapOverlay.Visible then
        renderMap(state)
    end
    renderNodeChoice(state)
end

return RunMapController
