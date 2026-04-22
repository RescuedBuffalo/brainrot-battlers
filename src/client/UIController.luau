--!strict
-- Builds the MainUI ScreenGui procedurally and re-renders declaratively from
-- the server's StateUpdate snapshots.
--
-- The UI is a single ScreenGui with five panels:
--   TopHud       -- gold / hp / level + xp bar / round / streak / army counter
--   Shop         -- 5 unit slots + reroll/BuyXP/StartCombat buttons
--   Bench        -- 9 tap-selectable unit slots
--   TraitPanel   -- active traits with tier indicators (computed from board)
--   Overlays     -- CombatOverlay (phase=combat), PostCombatOverlay (phase=postcombat)
--
-- Selection model: tap a bench slot or a board unit to select (outline pulses);
-- then tap a tile to place / move. Tap the same slot again to deselect.
-- SellButton (bottom-right) consumes the next tap on a bench/board unit.
--
-- Server remains authoritative for all actions; this controller never mutates
-- state locally, only fires RemoteEvents and re-renders when a StateUpdate
-- arrives.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local UnitDefinitions = require(sharedFolder:WaitForChild("UnitDefinitions"))
local TraitDefinitions = require(sharedFolder:WaitForChild("TraitDefinitions"))
local RarityDefinitions = require(sharedFolder:WaitForChild("RarityDefinitions"))
local Constants = require(sharedFolder:WaitForChild("Constants"))

local UIController = {}

local remotes: Folder
local player = Players.LocalPlayer
local lastState: any = nil

-- Selection: where the next tile-click will move *from*.
--   { loc = "bench" | "board", idx = number, x = number?, y = number? }
local selection: any = nil
local sellMode = false

-- Cached refs built in Init
local screenGui: ScreenGui
local roundLabel: TextLabel
local goldLabel: TextLabel
local hpLabel: TextLabel
local hpFill: Frame
local levelLabel: TextLabel
local xpFill: Frame
local streakLabel: TextLabel
local armyLabel: TextLabel
local shopSlots: { [number]: TextButton } = {}
local shopSlotLabels: { [number]: { TextLabel } } = {}
local rerollBtn: TextButton
local buyXpBtn: TextButton
local startCombatBtn: TextButton
local benchSlots: { [number]: TextButton } = {}
local traitList: Frame
local traitLabels: { [string]: TextLabel } = {}
local sellBtn: TextButton
local combatOverlay: Frame
local combatRoundLabel: TextLabel
local postCombatOverlay: Frame
local postCombatLabel: TextLabel
local postCombatIncome: TextLabel
local nextRoundBtn: TextButton
local endGameOverlay: Frame
local endGameLabel: TextLabel
local openCrateBtn: TextButton
local crateBadge: TextLabel
local collectionBtn: TextButton
local crateModal: Frame
local collectionModal: Frame
local collectionGrid: Frame

-- ---------- helpers ---------- --

local function rarityColor(r: string): Color3
    local def = RarityDefinitions[r]
    return def and def.color or Color3.fromRGB(160, 160, 160)
end

local function emojiFor(unitId: string?): string
    if not unitId then return "?" end
    local def = UnitDefinitions[unitId]
    return def and def.emoji or "?"
end

local function makeStroke(parent: Instance, color: Color3, thickness: number?): UIStroke
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 2
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function makeCorner(parent: Instance, radius: number?): UICorner
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = parent
    return c
end

local function makePadding(parent: Instance, n: number)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, n)
    p.PaddingBottom = UDim.new(0, n)
    p.PaddingLeft = UDim.new(0, n)
    p.PaddingRight = UDim.new(0, n)
    p.Parent = parent
end

local function starString(star: number): string
    if star <= 1 then return "" end
    return ("%d\u{2605}"):format(star)  -- "2★" / "3★"
end

-- ---------- construction ---------- --

local function buildTopHud(): Frame
    local hud = Instance.new("Frame")
    hud.Name = "TopHud"
    hud.Size = UDim2.new(1, -20, 0, 80)
    hud.Position = UDim2.fromOffset(10, 10)
    hud.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    hud.BackgroundTransparency = 0.15
    hud.BorderSizePixel = 0
    makeCorner(hud, 8)
    makePadding(hud, 8)

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 16)
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = hud

    local function chip(text: string, width: number, color: Color3): TextLabel
        local c = Instance.new("TextLabel")
        c.Size = UDim2.new(0, width, 1, -8)
        c.BackgroundColor3 = color
        c.BackgroundTransparency = 0.2
        c.Text = text
        c.TextColor3 = Color3.new(1, 1, 1)
        c.Font = Enum.Font.GothamBold
        c.TextScaled = true
        c.TextStrokeColor3 = Color3.new(0, 0, 0)
        c.TextStrokeTransparency = 0.5
        c.BorderSizePixel = 0
        makeCorner(c, 6)
        makePadding(c, 4)
        c.Parent = hud
        return c
    end

    roundLabel  = chip("R1/10", 100, Color3.fromRGB(80, 110, 180))
    goldLabel   = chip("💰 4",   100, Color3.fromRGB(170, 140, 40))

    -- HP with fill bar
    local hpBox = Instance.new("Frame")
    hpBox.Size = UDim2.fromOffset(130, 60)
    hpBox.BackgroundColor3 = Color3.fromRGB(140, 50, 60)
    hpBox.BackgroundTransparency = 0.2
    hpBox.BorderSizePixel = 0
    makeCorner(hpBox, 6)
    hpBox.Parent = hud
    hpFill = Instance.new("Frame")
    hpFill.Size = UDim2.fromScale(1, 1)
    hpFill.BackgroundColor3 = Color3.fromRGB(220, 60, 70)
    hpFill.BorderSizePixel = 0
    makeCorner(hpFill, 6)
    hpFill.Parent = hpBox
    hpLabel = Instance.new("TextLabel")
    hpLabel.Size = UDim2.fromScale(1, 1)
    hpLabel.BackgroundTransparency = 1
    hpLabel.Text = "❤️ 100"
    hpLabel.TextColor3 = Color3.new(1, 1, 1)
    hpLabel.Font = Enum.Font.GothamBold
    hpLabel.TextScaled = true
    hpLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    hpLabel.TextStrokeTransparency = 0
    hpLabel.ZIndex = 2
    hpLabel.Parent = hpBox

    -- Level + xp bar
    local lvlBox = Instance.new("Frame")
    lvlBox.Size = UDim2.fromOffset(140, 60)
    lvlBox.BackgroundColor3 = Color3.fromRGB(50, 80, 40)
    lvlBox.BackgroundTransparency = 0.3
    lvlBox.BorderSizePixel = 0
    makeCorner(lvlBox, 6)
    lvlBox.Parent = hud
    xpFill = Instance.new("Frame")
    xpFill.Size = UDim2.fromScale(0, 1)
    xpFill.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
    xpFill.BorderSizePixel = 0
    makeCorner(xpFill, 6)
    xpFill.Parent = lvlBox
    levelLabel = Instance.new("TextLabel")
    levelLabel.Size = UDim2.fromScale(1, 1)
    levelLabel.BackgroundTransparency = 1
    levelLabel.Text = "Lvl 2 (0/2)"
    levelLabel.TextColor3 = Color3.new(1, 1, 1)
    levelLabel.Font = Enum.Font.GothamBold
    levelLabel.TextScaled = true
    levelLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    levelLabel.TextStrokeTransparency = 0
    levelLabel.ZIndex = 2
    levelLabel.Parent = lvlBox

    streakLabel = chip("",      90, Color3.fromRGB(100, 100, 130))
    armyLabel   = chip("0/2",   90, Color3.fromRGB(60, 120, 80))

    -- View Map button: always visible in TopHud; click toggles the map overlay
    local mapBtn = Instance.new("TextButton")
    mapBtn.Name = "ViewMapBtn"
    mapBtn.Size = UDim2.new(0, 110, 1, -8)
    mapBtn.BackgroundColor3 = Color3.fromRGB(90, 80, 140)
    mapBtn.Text = "🗺️ Map"
    mapBtn.TextColor3 = Color3.new(1, 1, 1)
    mapBtn.Font = Enum.Font.GothamBold
    mapBtn.TextScaled = true
    mapBtn.BorderSizePixel = 0
    mapBtn.AutoButtonColor = true
    makeCorner(mapBtn, 6)
    makePadding(mapBtn, 4)
    mapBtn.MouseButton1Click:Connect(function()
        local pg = player:FindFirstChildOfClass("PlayerGui")
        local mainUI = pg and pg:FindFirstChild("MainUI")
        local overlay = mainUI and mainUI:FindFirstChild("RunMapOverlay")
        if overlay then overlay.Visible = not overlay.Visible end
    end)
    mapBtn.Parent = hud
    return hud
end

local function buildShop(): Frame
    local bar = Instance.new("Frame")
    bar.Name = "Shop"
    bar.AnchorPoint = Vector2.new(0.5, 1)
    bar.Position = UDim2.new(0.5, 0, 1, -10)
    bar.Size = UDim2.new(1, -40, 0, 120)
    bar.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    bar.BackgroundTransparency = 0.1
    bar.BorderSizePixel = 0
    makeCorner(bar, 10)
    makePadding(bar, 8)

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 8)
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Parent = bar

    local function btn(text: string, bg: Color3, onClick: () -> (), w: number): TextButton
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 1, -8)
        b.BackgroundColor3 = bg
        b.Text = text
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextScaled = true
        b.BorderSizePixel = 0
        b.AutoButtonColor = true
        makeCorner(b, 8)
        makePadding(b, 4)
        b.MouseButton1Click:Connect(onClick)
        b.Parent = bar
        return b
    end

    for i = 1, Constants.SHOP_SIZE do
        local slot = Instance.new("TextButton")
        slot.Size = UDim2.new(0, 120, 1, -8)
        slot.BackgroundColor3 = Color3.fromRGB(45, 48, 60)
        slot.Text = ""
        slot.BorderSizePixel = 0
        slot.AutoButtonColor = true
        makeCorner(slot, 8)
        slot.LayoutOrder = i
        slot.Parent = bar
        makeStroke(slot, Color3.fromRGB(140, 140, 160), 2)

        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Vertical
        list.VerticalAlignment = Enum.VerticalAlignment.Center
        list.HorizontalAlignment = Enum.HorizontalAlignment.Center
        list.Parent = slot

        local emoji = Instance.new("TextLabel")
        emoji.Size = UDim2.new(1, 0, 0.55, 0)
        emoji.BackgroundTransparency = 1
        emoji.Text = ""
        emoji.TextScaled = true
        emoji.Font = Enum.Font.GothamBold
        emoji.TextColor3 = Color3.new(1, 1, 1)
        emoji.LayoutOrder = 1
        emoji.Parent = slot

        local name = Instance.new("TextLabel")
        name.Size = UDim2.new(1, 0, 0.22, 0)
        name.BackgroundTransparency = 1
        name.Text = ""
        name.TextScaled = true
        name.Font = Enum.Font.GothamBold
        name.TextColor3 = Color3.new(1, 1, 1)
        name.LayoutOrder = 2
        name.Parent = slot

        local cost = Instance.new("TextLabel")
        cost.Size = UDim2.new(1, 0, 0.23, 0)
        cost.BackgroundTransparency = 1
        cost.Text = ""
        cost.TextScaled = true
        cost.Font = Enum.Font.Gotham
        cost.TextColor3 = Color3.fromRGB(255, 220, 120)
        cost.LayoutOrder = 3
        cost.Parent = slot

        local idx = i
        slot.MouseButton1Click:Connect(function()
            remotes.BuyUnit:FireServer(idx)
        end)
        shopSlots[i] = slot
        shopSlotLabels[i] = { emoji, name, cost }
    end

    rerollBtn = btn(("🎲 Reroll (%dg)"):format(Constants.REROLL_COST), Color3.fromRGB(110, 80, 160), function()
        remotes.RerollShop:FireServer()
    end, 130)
    buyXpBtn = btn(("⬆️ XP (%dg)"):format(Constants.XP_COST), Color3.fromRGB(60, 140, 80), function()
        remotes.BuyXP:FireServer()
    end, 130)
    startCombatBtn = btn("⚔️ FIGHT", Color3.fromRGB(200, 80, 60), function()
        remotes.StartCombat:FireServer()
    end, 130)
    startCombatBtn.LayoutOrder = 100

    return bar
end

local function buildBench(): Frame
    local bar = Instance.new("Frame")
    bar.Name = "Bench"
    bar.AnchorPoint = Vector2.new(0.5, 1)
    bar.Position = UDim2.new(0.5, 0, 1, -140)
    bar.Size = UDim2.new(1, -40, 0, 80)
    bar.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    bar.BackgroundTransparency = 0.2
    bar.BorderSizePixel = 0
    makeCorner(bar, 8)
    makePadding(bar, 6)

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 6)
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Parent = bar

    for i = 1, Constants.BENCH_SIZE do
        local slot = Instance.new("TextButton")
        slot.Size = UDim2.new(0, 66, 1, -8)
        slot.BackgroundColor3 = Color3.fromRGB(40, 43, 55)
        slot.Text = ""
        slot.BorderSizePixel = 0
        slot.AutoButtonColor = true
        makeCorner(slot, 6)
        slot.LayoutOrder = i
        slot.Parent = bar
        makeStroke(slot, Color3.fromRGB(90, 90, 110), 1)

        local emoji = Instance.new("TextLabel")
        emoji.Name = "Emoji"
        emoji.Size = UDim2.new(1, 0, 0.7, 0)
        emoji.Position = UDim2.fromScale(0, 0)
        emoji.BackgroundTransparency = 1
        emoji.Text = ""
        emoji.TextScaled = true
        emoji.Font = Enum.Font.GothamBold
        emoji.TextColor3 = Color3.new(1, 1, 1)
        emoji.Parent = slot

        local star = Instance.new("TextLabel")
        star.Name = "Star"
        star.Size = UDim2.new(1, 0, 0.3, 0)
        star.Position = UDim2.fromScale(0, 0.7)
        star.BackgroundTransparency = 1
        star.Text = ""
        star.TextScaled = true
        star.Font = Enum.Font.GothamBlack
        star.TextColor3 = Color3.fromRGB(255, 215, 0)
        star.TextStrokeColor3 = Color3.new(0, 0, 0)
        star.TextStrokeTransparency = 0.5
        star.Parent = slot

        local idx = i
        slot.MouseButton1Click:Connect(function()
            if not lastState then return end
            local unit = lastState.bench[idx]
            if not unit then
                -- Empty slot: maybe target for board->bench? Ignored for now.
                return
            end
            if sellMode then
                remotes.SellUnit:FireServer("bench", idx)
                sellMode = false
                UIController._updateSellVisual()
                return
            end
            if selection and selection.loc == "bench" and selection.idx == idx then
                selection = nil
            else
                selection = { loc = "bench", idx = idx }
            end
            UIController._refreshSelectionOutline()
        end)
        benchSlots[i] = slot
    end

    return bar
end

local function buildTraitPanel(): Frame
    local panel = Instance.new("Frame")
    panel.Name = "TraitPanel"
    panel.AnchorPoint = Vector2.new(0, 0.5)
    panel.Position = UDim2.new(0, 10, 0.5, 0)
    panel.Size = UDim2.fromOffset(180, 320)
    panel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    panel.BackgroundTransparency = 0.2
    panel.BorderSizePixel = 0
    makeCorner(panel, 8)
    makePadding(panel, 6)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 24)
    title.BackgroundTransparency = 1
    title.Text = "Traits"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = panel

    traitList = Instance.new("Frame")
    traitList.Name = "List"
    traitList.Size = UDim2.new(1, 0, 1, -30)
    traitList.Position = UDim2.fromOffset(0, 30)
    traitList.BackgroundTransparency = 1
    traitList.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 4)
    layout.Parent = traitList

    return panel
end

local function buildSellButton(): TextButton
    local b = Instance.new("TextButton")
    b.Name = "SellBtn"
    b.AnchorPoint = Vector2.new(1, 1)
    b.Position = UDim2.new(1, -10, 1, -140)
    b.Size = UDim2.fromOffset(100, 70)
    b.BackgroundColor3 = Color3.fromRGB(140, 50, 50)
    b.Text = "💰 Sell"
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextScaled = true
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    makeCorner(b, 8)
    makePadding(b, 6)
    b.MouseButton1Click:Connect(function()
        sellMode = not sellMode
        UIController._updateSellVisual()
    end)
    return b
end

local function buildCombatOverlay(): Frame
    local f = Instance.new("Frame")
    f.Name = "CombatOverlay"
    f.AnchorPoint = Vector2.new(0.5, 0)
    f.Position = UDim2.new(0.5, 0, 0, 100)
    f.Size = UDim2.fromOffset(400, 60)
    f.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    f.BackgroundTransparency = 0.15
    f.BorderSizePixel = 0
    f.Visible = false
    makeCorner(f, 8)

    combatRoundLabel = Instance.new("TextLabel")
    combatRoundLabel.Size = UDim2.fromScale(1, 1)
    combatRoundLabel.BackgroundTransparency = 1
    combatRoundLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
    combatRoundLabel.Font = Enum.Font.GothamBlack
    combatRoundLabel.TextScaled = true
    combatRoundLabel.Text = ""
    combatRoundLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    combatRoundLabel.TextStrokeTransparency = 0
    combatRoundLabel.Parent = f

    return f
end

local function buildPostCombatOverlay(): Frame
    local f = Instance.new("Frame")
    f.Name = "PostCombatOverlay"
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromScale(0.5, 0.5)
    f.Size = UDim2.fromOffset(420, 280)
    f.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    f.BackgroundTransparency = 0.05
    f.BorderSizePixel = 0
    f.Visible = false
    makeCorner(f, 12)
    makePadding(f, 20)

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 10)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = f

    postCombatLabel = Instance.new("TextLabel")
    postCombatLabel.Size = UDim2.new(1, 0, 0, 60)
    postCombatLabel.BackgroundTransparency = 1
    postCombatLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
    postCombatLabel.Font = Enum.Font.GothamBlack
    postCombatLabel.TextScaled = true
    postCombatLabel.Text = "VICTORY"
    postCombatLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    postCombatLabel.TextStrokeTransparency = 0
    postCombatLabel.Parent = f

    postCombatIncome = Instance.new("TextLabel")
    postCombatIncome.Size = UDim2.new(1, 0, 0, 100)
    postCombatIncome.BackgroundTransparency = 1
    postCombatIncome.TextColor3 = Color3.new(1, 1, 1)
    postCombatIncome.Font = Enum.Font.Gotham
    postCombatIncome.TextScaled = true
    postCombatIncome.Text = ""
    postCombatIncome.Parent = f

    nextRoundBtn = Instance.new("TextButton")
    nextRoundBtn.Size = UDim2.new(0, 200, 0, 50)
    nextRoundBtn.BackgroundColor3 = Color3.fromRGB(80, 160, 90)
    nextRoundBtn.Text = "➡️ NEXT ROUND"
    nextRoundBtn.TextColor3 = Color3.new(1, 1, 1)
    nextRoundBtn.Font = Enum.Font.GothamBold
    nextRoundBtn.TextScaled = true
    nextRoundBtn.BorderSizePixel = 0
    makeCorner(nextRoundBtn, 8)
    makePadding(nextRoundBtn, 6)
    nextRoundBtn.MouseButton1Click:Connect(function()
        remotes.NextRound:FireServer()
    end)
    nextRoundBtn.Parent = f

    return f
end

local function buildEndGameOverlay(): Frame
    local f = Instance.new("Frame")
    f.Name = "EndGameOverlay"
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromScale(0.5, 0.5)
    f.Size = UDim2.fromOffset(500, 300)
    f.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    f.BackgroundTransparency = 0
    f.BorderSizePixel = 0
    f.Visible = false
    makeCorner(f, 12)
    makePadding(f, 20)

    endGameLabel = Instance.new("TextLabel")
    endGameLabel.Size = UDim2.new(1, 0, 1, 0)
    endGameLabel.BackgroundTransparency = 1
    endGameLabel.TextColor3 = Color3.new(1, 1, 1)
    endGameLabel.Font = Enum.Font.GothamBlack
    endGameLabel.TextScaled = true
    endGameLabel.Text = ""
    endGameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    endGameLabel.TextStrokeTransparency = 0
    endGameLabel.Parent = f

    return f
end

-- ---------- render ---------- --

local function buildSideButtons(): (TextButton, TextButton)
    -- Stacked below the sell button on the right edge.
    local openBtn = Instance.new("TextButton")
    openBtn.Name = "OpenCrateBtn"
    openBtn.AnchorPoint = Vector2.new(1, 0)
    openBtn.Position = UDim2.new(1, -10, 0, 100)
    openBtn.Size = UDim2.fromOffset(120, 70)
    openBtn.BackgroundColor3 = Color3.fromRGB(180, 110, 50)
    openBtn.Text = "🎁 Open Crate"
    openBtn.TextColor3 = Color3.new(1, 1, 1)
    openBtn.Font = Enum.Font.GothamBold
    openBtn.TextScaled = true
    openBtn.BorderSizePixel = 0
    openBtn.AutoButtonColor = true
    makeCorner(openBtn, 8)
    makePadding(openBtn, 6)
    openBtn.MouseButton1Click:Connect(function()
        remotes.OpenCrate:FireServer()
    end)

    -- Pending-count badge
    crateBadge = Instance.new("TextLabel")
    crateBadge.AnchorPoint = Vector2.new(1, 0)
    crateBadge.Position = UDim2.new(1, 6, 0, -6)
    crateBadge.Size = UDim2.fromOffset(28, 28)
    crateBadge.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    crateBadge.Text = "0"
    crateBadge.TextColor3 = Color3.new(1, 1, 1)
    crateBadge.Font = Enum.Font.GothamBlack
    crateBadge.TextScaled = true
    crateBadge.BorderSizePixel = 0
    crateBadge.Visible = false
    makeCorner(crateBadge, 14)
    crateBadge.Parent = openBtn

    local colBtn = Instance.new("TextButton")
    colBtn.Name = "CollectionBtn"
    colBtn.AnchorPoint = Vector2.new(1, 0)
    colBtn.Position = UDim2.new(1, -10, 0, 180)
    colBtn.Size = UDim2.fromOffset(120, 50)
    colBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 180)
    colBtn.Text = "📚 Collection"
    colBtn.TextColor3 = Color3.new(1, 1, 1)
    colBtn.Font = Enum.Font.GothamBold
    colBtn.TextScaled = true
    colBtn.BorderSizePixel = 0
    colBtn.AutoButtonColor = true
    makeCorner(colBtn, 8)
    makePadding(colBtn, 6)
    colBtn.MouseButton1Click:Connect(function()
        if collectionModal then
            collectionModal.Visible = not collectionModal.Visible
        end
    end)

    return openBtn, colBtn
end

local function buildCrateModal(): Frame
    local m = Instance.new("Frame")
    m.Name = "CrateModal"
    m.AnchorPoint = Vector2.new(0.5, 0.5)
    m.Position = UDim2.fromScale(0.5, 0.5)
    m.Size = UDim2.new(1, 0, 1, 0)
    m.BackgroundColor3 = Color3.new(0, 0, 0)
    m.BackgroundTransparency = 0.4
    m.BorderSizePixel = 0
    m.Visible = false
    m.ZIndex = 10

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.fromOffset(360, 460)
    card.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    card.BorderSizePixel = 0
    card.ZIndex = 11
    makeCorner(card, 12)
    makeStroke(card, Color3.fromRGB(140, 140, 160), 3)
    card.Parent = m

    -- Contents: title, big emoji, rarity label, outcome text, close btn
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 36)
    title.Position = UDim2.fromOffset(0, 12)
    title.BackgroundTransparency = 1
    title.Text = "Opening..."
    title.TextColor3 = Color3.fromRGB(255, 220, 120)
    title.Font = Enum.Font.GothamBlack
    title.TextScaled = true
    title.ZIndex = 12
    title.Parent = card

    local emoji = Instance.new("TextLabel")
    emoji.Name = "Emoji"
    emoji.AnchorPoint = Vector2.new(0.5, 0.5)
    emoji.Position = UDim2.fromScale(0.5, 0.42)
    emoji.Size = UDim2.fromOffset(200, 200)
    emoji.BackgroundTransparency = 1
    emoji.Text = "🎁"
    emoji.TextScaled = true
    emoji.Font = Enum.Font.GothamBlack
    emoji.TextColor3 = Color3.new(1, 1, 1)
    emoji.ZIndex = 12
    emoji.Parent = card

    local rarityLabel = Instance.new("TextLabel")
    rarityLabel.Name = "RarityLabel"
    rarityLabel.Size = UDim2.new(1, -20, 0, 40)
    rarityLabel.Position = UDim2.fromOffset(10, 300)
    rarityLabel.BackgroundTransparency = 1
    rarityLabel.Text = ""
    rarityLabel.TextColor3 = Color3.new(1, 1, 1)
    rarityLabel.Font = Enum.Font.GothamBold
    rarityLabel.TextScaled = true
    rarityLabel.ZIndex = 12
    rarityLabel.Parent = card

    local outcomeLabel = Instance.new("TextLabel")
    outcomeLabel.Name = "OutcomeLabel"
    outcomeLabel.Size = UDim2.new(1, -20, 0, 32)
    outcomeLabel.Position = UDim2.fromOffset(10, 350)
    outcomeLabel.BackgroundTransparency = 1
    outcomeLabel.Text = ""
    outcomeLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
    outcomeLabel.Font = Enum.Font.Gotham
    outcomeLabel.TextScaled = true
    outcomeLabel.ZIndex = 12
    outcomeLabel.Parent = card

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseBtn"
    closeBtn.AnchorPoint = Vector2.new(0.5, 1)
    closeBtn.Position = UDim2.new(0.5, 0, 1, -14)
    closeBtn.Size = UDim2.fromOffset(200, 40)
    closeBtn.BackgroundColor3 = Color3.fromRGB(80, 120, 180)
    closeBtn.Text = "✓ Continue"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextScaled = true
    closeBtn.BorderSizePixel = 0
    closeBtn.Visible = false
    closeBtn.ZIndex = 12
    makeCorner(closeBtn, 8)
    makePadding(closeBtn, 4)
    closeBtn.MouseButton1Click:Connect(function()
        m.Visible = false
    end)
    closeBtn.Parent = card

    return m
end

local function buildCollectionModal(): Frame
    local m = Instance.new("Frame")
    m.Name = "CollectionModal"
    m.AnchorPoint = Vector2.new(0.5, 0.5)
    m.Position = UDim2.fromScale(0.5, 0.5)
    m.Size = UDim2.new(1, 0, 1, 0)
    m.BackgroundColor3 = Color3.new(0, 0, 0)
    m.BackgroundTransparency = 0.4
    m.BorderSizePixel = 0
    m.Visible = false
    m.ZIndex = 10

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.fromOffset(720, 520)
    card.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    card.BorderSizePixel = 0
    card.ZIndex = 11
    makeCorner(card, 12)
    makeStroke(card, Color3.fromRGB(140, 140, 160), 2)
    card.Parent = m

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.fromOffset(0, 10)
    title.BackgroundTransparency = 1
    title.Text = "📚 Collection"
    title.TextColor3 = Color3.fromRGB(255, 220, 120)
    title.Font = Enum.Font.GothamBlack
    title.TextScaled = true
    title.ZIndex = 12
    title.Parent = card

    collectionGrid = Instance.new("Frame")
    collectionGrid.Name = "Grid"
    collectionGrid.AnchorPoint = Vector2.new(0.5, 0)
    collectionGrid.Position = UDim2.new(0.5, 0, 0, 60)
    collectionGrid.Size = UDim2.new(1, -40, 1, -120)
    collectionGrid.BackgroundTransparency = 1
    collectionGrid.ZIndex = 12
    collectionGrid.Parent = card

    local layout = Instance.new("UIGridLayout")
    layout.CellSize = UDim2.fromOffset(128, 140)
    layout.CellPadding = UDim2.fromOffset(8, 8)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Parent = collectionGrid

    local closeBtn = Instance.new("TextButton")
    closeBtn.AnchorPoint = Vector2.new(0.5, 1)
    closeBtn.Position = UDim2.new(0.5, 0, 1, -14)
    closeBtn.Size = UDim2.fromOffset(200, 40)
    closeBtn.BackgroundColor3 = Color3.fromRGB(80, 120, 180)
    closeBtn.Text = "Close"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextScaled = true
    closeBtn.BorderSizePixel = 0
    closeBtn.ZIndex = 12
    makeCorner(closeBtn, 8)
    makePadding(closeBtn, 4)
    closeBtn.MouseButton1Click:Connect(function()
        m.Visible = false
    end)
    closeBtn.Parent = card

    return m
end

local function renderCollection(state: any)
    if not collectionGrid then return end
    local coll = state.collection or {}
    -- Stable alphabetical order
    local sortedIds = {}
    for uid in pairs(UnitDefinitions) do table.insert(sortedIds, uid) end
    table.sort(sortedIds)

    for _, uid in ipairs(sortedIds) do
        local def = UnitDefinitions[uid]
        local card = collectionGrid:FindFirstChild(uid)
        if not card then
            card = Instance.new("Frame")
            card.Name = uid
            card.BackgroundColor3 = Color3.fromRGB(35, 38, 50)
            card.BorderSizePixel = 0
            card.ZIndex = 12
            makeCorner(card, 8)
            makeStroke(card, Color3.fromRGB(90, 90, 110), 2)

            local em = Instance.new("TextLabel")
            em.Name = "Emoji"
            em.Size = UDim2.new(1, 0, 0.6, 0)
            em.BackgroundTransparency = 1
            em.Text = def.emoji
            em.TextScaled = true
            em.Font = Enum.Font.GothamBold
            em.TextColor3 = Color3.new(1, 1, 1)
            em.ZIndex = 13
            em.Parent = card

            local nm = Instance.new("TextLabel")
            nm.Name = "Name"
            nm.Size = UDim2.new(1, 0, 0.2, 0)
            nm.Position = UDim2.fromScale(0, 0.6)
            nm.BackgroundTransparency = 1
            nm.Text = def.name
            nm.TextScaled = true
            nm.Font = Enum.Font.GothamBold
            nm.TextColor3 = Color3.new(1, 1, 1)
            nm.ZIndex = 13
            nm.Parent = card

            local rLabel = Instance.new("TextLabel")
            rLabel.Name = "Rarity"
            rLabel.Size = UDim2.new(1, 0, 0.2, 0)
            rLabel.Position = UDim2.fromScale(0, 0.8)
            rLabel.BackgroundTransparency = 1
            rLabel.Text = ""
            rLabel.TextScaled = true
            rLabel.Font = Enum.Font.GothamBold
            rLabel.ZIndex = 13
            rLabel.Parent = card

            card.Parent = collectionGrid
        end

        local rarity = coll[uid]
        local stroke = card:FindFirstChildOfClass("UIStroke")
        local rLabel = card:FindFirstChild("Rarity") :: TextLabel
        local emojiLbl = card:FindFirstChild("Emoji") :: TextLabel
        if rarity then
            local def2 = RarityDefinitions[rarity]
            if def2 and stroke then
                stroke.Color = def2.color
                stroke.Thickness = 3
            end
            rLabel.Text = rarity:upper()
            rLabel.TextColor3 = (def2 and def2.color) or Color3.new(1, 1, 1)
            emojiLbl.TextTransparency = 0
        else
            if stroke then
                stroke.Color = Color3.fromRGB(60, 60, 75)
                stroke.Thickness = 1
            end
            rLabel.Text = "not owned"
            rLabel.TextColor3 = Color3.fromRGB(130, 130, 140)
            emojiLbl.TextTransparency = 0.7
        end
    end
end

local function animateCrateReveal(drop)
    if not crateModal then return end
    crateModal.Visible = true
    local card = crateModal:FindFirstChild("Card") :: Frame
    local title = card:FindFirstChild("Title") :: TextLabel
    local emoji = card:FindFirstChild("Emoji") :: TextLabel
    local rarityLbl = card:FindFirstChild("RarityLabel") :: TextLabel
    local outcomeLbl = card:FindFirstChild("OutcomeLabel") :: TextLabel
    local closeBtn = card:FindFirstChild("CloseBtn") :: TextButton

    -- Reset state for each new reveal
    title.Text = ("Opening %s crate..."):format(drop.tier or "common")
    emoji.Text = "🎁"
    rarityLbl.Text = ""
    outcomeLbl.Text = ""
    closeBtn.Visible = false
    local stroke = card:FindFirstChildOfClass("UIStroke")
    if stroke then stroke.Color = Color3.fromRGB(140, 140, 160) end

    task.spawn(function()
        -- Shake phase
        local shakeDur = 1.2
        local t0 = os.clock()
        while os.clock() - t0 < shakeDur do
            local a = (os.clock() - t0) / shakeDur
            local angle = math.sin(a * 60) * (3 + a * 6)
            emoji.Rotation = angle
            task.wait()
        end
        emoji.Rotation = 0

        -- Burst: scale pulse on the emoji background
        local def = RarityDefinitions[drop.rarity]
        local rColor = (def and def.color) or Color3.new(1, 1, 1)

        -- Flash card outline with rarity color
        if stroke then
            stroke.Color = rColor
            stroke.Thickness = 6
        end

        -- Reveal unit emoji
        local unitDef = UnitDefinitions[drop.unitId]
        if unitDef then
            emoji.Text = unitDef.emoji
        end

        -- Optional burst particles on the attachment point of the card -- using
        -- a simple tween scale instead since we're in GUI space.
        local originalSize = emoji.Size
        emoji.Size = UDim2.fromOffset(80, 80)
        local tween = TweenService:Create(emoji, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = originalSize,
        })
        tween:Play()
        task.wait(0.3)

        title.Text = unitDef and unitDef.name or drop.unitId
        rarityLbl.Text = (drop.rarity or "common"):upper() .. " " .. (unitDef and unitDef.emoji or "")
        rarityLbl.TextColor3 = rColor

        if drop.upgraded then
            local prev = drop.previousRarity and drop.previousRarity:upper() or "NONE"
            outcomeLbl.Text = ("✨ UPGRADED (%s → %s)"):format(prev, (drop.rarity or "?"):upper())
            outcomeLbl.TextColor3 = Color3.fromRGB(255, 220, 120)
        else
            outcomeLbl.Text = ("Duplicate → +%d gold"):format(drop.goldRefund or 0)
            outcomeLbl.TextColor3 = Color3.fromRGB(170, 200, 170)
        end

        closeBtn.Visible = true
    end)
end

local function renderShop(state: any)
    for i = 1, Constants.SHOP_SIZE do
        local slot = shopSlots[i]
        local labels = shopSlotLabels[i]
        local shopSlot = state.shop[i]
        if shopSlot and shopSlot.unitId then
            local def = UnitDefinitions[shopSlot.unitId]
            labels[1].Text = def.emoji
            labels[2].Text = def.name
            labels[3].Text = ("💰 %d"):format(def.cost)
            slot.BackgroundColor3 = Color3.fromRGB(45, 48, 60)
            slot.Active = true
            local stroke = slot:FindFirstChildOfClass("UIStroke")
            if stroke then
                stroke.Color = rarityColor("common")
            end
            local canAfford = state.gold >= def.cost
            slot.BackgroundTransparency = canAfford and 0 or 0.5
        else
            labels[1].Text = ""
            labels[2].Text = ""
            labels[3].Text = ""
            slot.BackgroundColor3 = Color3.fromRGB(30, 32, 42)
            slot.BackgroundTransparency = 0.5
        end
    end

    rerollBtn.BackgroundTransparency = (state.gold >= Constants.REROLL_COST) and 0 or 0.5
    buyXpBtn.BackgroundTransparency = (state.gold >= Constants.XP_COST and state.level < Constants.MAX_LEVEL) and 0 or 0.5
    startCombatBtn.BackgroundTransparency = (#state.board > 0) and 0 or 0.5
end

local function renderBench(state: any)
    for i = 1, Constants.BENCH_SIZE do
        local slot = benchSlots[i]
        local unit = state.bench[i]
        local emoji = slot:FindFirstChild("Emoji") :: TextLabel
        local star = slot:FindFirstChild("Star") :: TextLabel
        local stroke = slot:FindFirstChildOfClass("UIStroke")
        if unit then
            emoji.Text = emojiFor(unit.unitId)
            star.Text = starString(unit.star)
            slot.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
            if stroke then stroke.Color = rarityColor(unit.rarity); stroke.Thickness = 3 end
        else
            emoji.Text = ""
            star.Text = ""
            slot.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
            if stroke then stroke.Color = Color3.fromRGB(60, 60, 75); stroke.Thickness = 1 end
        end
    end
end

local function computeTraits(board: { any }): { [string]: { count: number, distinct: number } }
    local distinctIds: { [string]: { [string]: true } } = {}
    for _, b in ipairs(board) do
        local def = UnitDefinitions[b.unitId]
        if def then
            for _, t in ipairs(def.traits) do
                distinctIds[t] = distinctIds[t] or {}
                distinctIds[t][b.unitId] = true
            end
        end
    end
    local out: { [string]: { count: number, distinct: number } } = {}
    for trait, set in pairs(distinctIds) do
        local n = 0
        for _ in pairs(set) do n += 1 end
        out[trait] = { count = n, distinct = n }
    end
    return out
end

local function renderTraitPanel(state: any)
    local tCounts = computeTraits(state.board)

    -- Ensure a label exists for every trait currently represented on the board
    local alive: { [string]: true } = {}
    for trait, info in pairs(tCounts) do
        alive[trait] = true
        local td = TraitDefinitions[trait]
        if not td then continue end
        local label = traitLabels[trait]
        if not label then
            label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, 0, 0, 28)
            label.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
            label.BackgroundTransparency = 0.2
            label.TextColor3 = Color3.new(1, 1, 1)
            label.Font = Enum.Font.GothamBold
            label.TextScaled = true
            label.BorderSizePixel = 0
            makeCorner(label, 4)
            makePadding(label, 4)
            label.Parent = traitList
            traitLabels[trait] = label
        end
        local activeTier: number? = nil
        for i, tier in ipairs(td.tiers) do
            if info.count >= tier[1] then activeTier = i end
        end
        if activeTier then
            label.Text = ("%s %s  %d/%d"):format(td.emoji, td.name, info.count, td.tiers[activeTier][1])
            label.TextColor3 = Color3.fromRGB(255, 220, 120)
            label.BackgroundTransparency = 0
        else
            local nextReq = td.tiers[1][1]
            label.Text = ("%s %s  %d/%d"):format(td.emoji, td.name, info.count, nextReq)
            label.TextColor3 = Color3.fromRGB(180, 180, 200)
            label.BackgroundTransparency = 0.5
        end
    end
    -- Prune traits that are no longer present
    for trait, label in pairs(traitLabels) do
        if not alive[trait] then
            label:Destroy()
            traitLabels[trait] = nil
        end
    end
end

local function renderTopHud(state: any)
    roundLabel.Text = ("R%d/%d"):format(state.round, Constants.TOTAL_ROUNDS)
    goldLabel.Text = ("💰 %d"):format(state.gold)
    hpLabel.Text = ("❤️ %d"):format(state.hp)
    hpFill.Size = UDim2.fromScale(math.clamp(state.hp / Constants.STARTING_HP, 0, 1), 1)

    if state.level >= Constants.MAX_LEVEL then
        levelLabel.Text = ("Lvl %d (MAX)"):format(state.level)
        xpFill.Size = UDim2.fromScale(1, 1)
    else
        local xpToNext = state.xpToNext or 1
        levelLabel.Text = ("Lvl %d (%d/%d)"):format(state.level, state.xp, xpToNext)
        xpFill.Size = UDim2.fromScale(math.clamp(state.xp / math.max(1, xpToNext), 0, 1), 1)
    end

    if state.streakType == "none" or state.streak <= 1 then
        streakLabel.Text = ""
    else
        local arrow = state.streakType == "win" and "🔥" or "💀"
        streakLabel.Text = ("%s %d"):format(arrow, state.streak)
    end

    local armyN = #state.board
    local cap = state.level
    armyLabel.Text = ("%d/%d"):format(armyN, cap)
    if armyN >= cap then
        armyLabel.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
    else
        armyLabel.BackgroundColor3 = Color3.fromRGB(60, 120, 80)
    end
end

local function renderOverlays(state: any)
    local inCombat = state.phase == "combat"
    local inPostCombat = state.phase == "postcombat" or state.phase == "shopNode"
    local isEnd = state.phase == "victory" or state.phase == "defeat"
    -- Phase 12: shop UI is reused for both pre-combat shop (phase=shop) AND
    -- standalone shop nodes (phase=shopNode). Start Combat button only shows
    -- in the former; shopNode gets a "Leave Shop" button on the overlay.

    combatOverlay.Visible = inCombat
    if inCombat then
        combatRoundLabel.Text = ("⚔️ Round %d"):format(state.round)
    end

    -- PostCombatOverlay now doubles as the "continue" prompt for shopNode too
    postCombatOverlay.Visible = (state.phase == "postcombat") or (state.phase == "shopNode")
    if state.phase == "postcombat" and state.lastResult then
        local r = state.lastResult
        postCombatLabel.Text = r.outcome == "win" and "🏆 VICTORY" or "💀 DEFEAT"
        postCombatLabel.TextColor3 = r.outcome == "win"
            and Color3.fromRGB(255, 220, 100)
            or Color3.fromRGB(255, 140, 140)
        local ib = r.incomeBreakdown or {}
        postCombatIncome.Text = ("Income: base %d + interest %d + streak %d + stolen %d"):format(
            ib.base or 0, ib.interest or 0, ib.streak or 0, ib.stolen or 0
        )
        nextRoundBtn.Text = "➡️ CONTINUE"
    elseif state.phase == "shopNode" then
        postCombatLabel.Text = "🛒 Shop Node"
        postCombatLabel.TextColor3 = Color3.fromRGB(120, 200, 240)
        postCombatIncome.Text = "Browse, buy, reroll. No fight here."
        nextRoundBtn.Text = "➡️ LEAVE SHOP"
    end

    endGameOverlay.Visible = isEnd
    if isEnd then
        endGameLabel.Text = state.phase == "victory"
            and ("🏆 YOU WON!\nCombats won: %d  |  Total wins: %d"):format(state.combatsWon or 0, state.totalWins)
            or ("💀 DEFEAT\nCombats won: %d"):format(state.combatsWon or 0)
    end

    -- Lock shop slots during combat only
    for _, slot in pairs(shopSlots) do slot.Active = not inCombat end
    rerollBtn.Active = not inCombat
    buyXpBtn.Active = not inCombat
    -- FIGHT button only shows in pre-combat shop phase
    startCombatBtn.Visible = state.phase == "shop"
end

function UIController._refreshSelectionOutline()
    for i, slot in pairs(benchSlots) do
        local stroke = slot:FindFirstChildOfClass("UIStroke")
        if stroke then
            if selection and selection.loc == "bench" and selection.idx == i then
                stroke.Color = Color3.fromRGB(255, 255, 120)
                stroke.Thickness = 4
            else
                local unit = lastState and lastState.bench[i]
                if unit then
                    stroke.Color = rarityColor(unit.rarity)
                    stroke.Thickness = 3
                else
                    stroke.Color = Color3.fromRGB(60, 60, 75)
                    stroke.Thickness = 1
                end
            end
        end
    end
end

function UIController._updateSellVisual()
    sellBtn.BackgroundColor3 = sellMode
        and Color3.fromRGB(210, 80, 80)
        or Color3.fromRGB(140, 50, 50)
    sellBtn.Text = sellMode and "💰 Sell\n(tap unit)" or "💰 Sell"
end

-- ---------- public API ---------- --

function UIController.Init(deps)
    remotes = deps.Remotes

    local pg = player:WaitForChild("PlayerGui")
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MainUI"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = pg

    buildTopHud().Parent = screenGui
    buildShop().Parent = screenGui
    buildBench().Parent = screenGui
    buildTraitPanel().Parent = screenGui
    sellBtn = buildSellButton()
    sellBtn.Parent = screenGui
    combatOverlay = buildCombatOverlay()
    combatOverlay.Parent = screenGui
    postCombatOverlay = buildPostCombatOverlay()
    postCombatOverlay.Parent = screenGui
    endGameOverlay = buildEndGameOverlay()
    endGameOverlay.Parent = screenGui

    openCrateBtn, collectionBtn = buildSideButtons()
    openCrateBtn.Parent = screenGui
    collectionBtn.Parent = screenGui
    crateModal = buildCrateModal()
    crateModal.Parent = screenGui
    collectionModal = buildCollectionModal()
    collectionModal.Parent = screenGui

    UIController._updateSellVisual()
end

local function renderCrateButton(state: any)
    if not crateBadge or not openCrateBtn then return end
    local pending = #(state.pendingCrates or {})
    if pending > 0 then
        crateBadge.Text = tostring(pending)
        crateBadge.Visible = true
        openCrateBtn.BackgroundColor3 = Color3.fromRGB(220, 140, 60)
        openCrateBtn.AutoButtonColor = true
    else
        crateBadge.Visible = false
        openCrateBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
    end
end

function UIController.Render(state)
    if not state then return end
    lastState = state
    renderTopHud(state)
    renderShop(state)
    renderBench(state)
    renderTraitPanel(state)
    renderOverlays(state)
    renderCrateButton(state)
    renderCollection(state)
    UIController._refreshSelectionOutline()
end

function UIController.ShowCrateReveal(drop)
    animateCrateReveal(drop)
end

-- Called by Input when the user clicks a tile. x,y are 0..5 tile coords.
function UIController.OnTileClick(x: number, y: number)
    if not lastState or lastState.phase ~= "shop" then return end

    -- Is there a unit at this tile on the player board?
    local boardIdx: number? = nil
    for i, u in ipairs(lastState.board) do
        if u.x == x and u.y == y then
            boardIdx = i
            break
        end
    end

    if sellMode then
        if boardIdx then
            remotes.SellUnit:FireServer("board", boardIdx)
        end
        sellMode = false
        UIController._updateSellVisual()
        return
    end

    if selection and selection.loc == "bench" then
        -- Try to place bench -> board at (x, y)
        remotes.PlaceUnit:FireServer({
            fromLoc = "bench", fromIdx = selection.idx,
            toLoc = "board", toIdx = 0, x = x, y = y,
        })
        selection = nil
        UIController._refreshSelectionOutline()
        return
    end

    if selection and selection.loc == "board" then
        remotes.PlaceUnit:FireServer({
            fromLoc = "board", fromIdx = selection.idx,
            toLoc = "board", toIdx = 0, x = x, y = y,
        })
        selection = nil
        UIController._refreshSelectionOutline()
        return
    end

    -- No selection yet, but tapped a board unit -> select it
    if boardIdx then
        selection = { loc = "board", idx = boardIdx, x = x, y = y }
        UIController._refreshSelectionOutline()
    end
end

return UIController
