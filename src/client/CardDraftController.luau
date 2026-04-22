--!strict
-- Renders the event (2-of) and forge (3-of) card-draft modals plus the
-- unit-target picker that follows Tung Tung's Nap. All three reuse the
-- same modal shell; they differ in the layout of the offered cards and
-- the remote payload sent on pick.
--
-- Controller reads state.pendingDraft (a {kind, options} table set by
-- GameManager on nodeEntry) and state.pendingTarget (set when a card
-- needs a unit target). Clears itself when phase != event/forge/unitTarget.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDraftController = {}

local player = Players.LocalPlayer
local remotes: Folder
local CardDefinitions
local UnitDefinitions
local RarityDefinitions

local draftModal: Frame
local draftTitle: TextLabel
local cardRow: Frame
local targetModal: Frame
local targetTitle: TextLabel
local targetGrid: Frame
local pendingCardId: string?

local function makeCorner(parent: Instance, radius: number?)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
end

local function makeStroke(parent: Instance, color: Color3, thickness: number?)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 2
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
end

local function buildDraftModal(parent: ScreenGui)
    draftModal = Instance.new("Frame")
    draftModal.Name = "CardDraftModal"
    draftModal.AnchorPoint = Vector2.new(0.5, 0.5)
    draftModal.Position = UDim2.fromScale(0.5, 0.5)
    draftModal.Size = UDim2.fromOffset(720, 400)
    draftModal.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    draftModal.BorderSizePixel = 0
    draftModal.Visible = false
    draftModal.ZIndex = 18
    makeCorner(draftModal, 12)
    makeStroke(draftModal, Color3.fromRGB(200, 160, 80), 3)
    draftModal.Parent = parent

    draftTitle = Instance.new("TextLabel")
    draftTitle.Size = UDim2.new(1, -20, 0, 40)
    draftTitle.Position = UDim2.fromOffset(10, 12)
    draftTitle.BackgroundTransparency = 1
    draftTitle.Text = ""
    draftTitle.TextColor3 = Color3.fromRGB(255, 220, 120)
    draftTitle.Font = Enum.Font.GothamBlack
    draftTitle.TextScaled = true
    draftTitle.ZIndex = 19
    draftTitle.Parent = draftModal

    cardRow = Instance.new("Frame")
    cardRow.AnchorPoint = Vector2.new(0.5, 0.5)
    cardRow.Position = UDim2.fromScale(0.5, 0.55)
    cardRow.Size = UDim2.new(1, -40, 0, 280)
    cardRow.BackgroundTransparency = 1
    cardRow.ZIndex = 19
    cardRow.Parent = draftModal

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 16)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = cardRow
end

local function buildTargetModal(parent: ScreenGui)
    targetModal = Instance.new("Frame")
    targetModal.Name = "UnitTargetModal"
    targetModal.AnchorPoint = Vector2.new(0.5, 0.5)
    targetModal.Position = UDim2.fromScale(0.5, 0.5)
    targetModal.Size = UDim2.fromOffset(600, 360)
    targetModal.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    targetModal.BorderSizePixel = 0
    targetModal.Visible = false
    targetModal.ZIndex = 20
    makeCorner(targetModal, 12)
    makeStroke(targetModal, Color3.fromRGB(120, 180, 240), 3)
    targetModal.Parent = parent

    targetTitle = Instance.new("TextLabel")
    targetTitle.Size = UDim2.new(1, -20, 0, 36)
    targetTitle.Position = UDim2.fromOffset(10, 10)
    targetTitle.BackgroundTransparency = 1
    targetTitle.Text = "Pick a unit"
    targetTitle.TextColor3 = Color3.fromRGB(200, 230, 255)
    targetTitle.Font = Enum.Font.GothamBlack
    targetTitle.TextScaled = true
    targetTitle.ZIndex = 21
    targetTitle.Parent = targetModal

    targetGrid = Instance.new("Frame")
    targetGrid.AnchorPoint = Vector2.new(0.5, 0)
    targetGrid.Position = UDim2.new(0.5, 0, 0, 56)
    targetGrid.Size = UDim2.new(1, -40, 1, -80)
    targetGrid.BackgroundTransparency = 1
    targetGrid.ZIndex = 21
    targetGrid.Parent = targetModal

    local layout = Instance.new("UIGridLayout")
    layout.CellSize = UDim2.fromOffset(96, 110)
    layout.CellPadding = UDim2.fromOffset(8, 8)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Parent = targetGrid
end

local function clearChildren(f: Instance)
    for _, c in ipairs(f:GetChildren()) do
        if not c:IsA("UILayout") then c:Destroy() end
    end
end

local function renderCards(options: { string }, kind: string)
    clearChildren(cardRow)
    draftTitle.Text = kind == "event" and "📜 Event — Pick 1" or "🔨 Forge — Pick 1 (run-long)"

    for i, cardId in ipairs(options) do
        local def = CardDefinitions.CARDS[cardId]
        if not def then continue end

        local card = Instance.new("TextButton")
        card.Size = UDim2.fromOffset(200, 280)
        card.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
        card.BorderSizePixel = 0
        card.AutoButtonColor = true
        card.Text = ""
        card.LayoutOrder = i
        card.ZIndex = 20
        makeCorner(card, 10)
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Color = kind == "forge" and Color3.fromRGB(255, 180, 60) or Color3.fromRGB(150, 200, 150)
        stroke.Parent = card

        local emoji = Instance.new("TextLabel")
        emoji.Size = UDim2.new(1, 0, 0, 80)
        emoji.Position = UDim2.fromOffset(0, 10)
        emoji.BackgroundTransparency = 1
        emoji.Text = def.emoji
        emoji.TextScaled = true
        emoji.Font = Enum.Font.GothamBlack
        emoji.TextColor3 = Color3.new(1, 1, 1)
        emoji.ZIndex = 21
        emoji.Parent = card

        local name = Instance.new("TextLabel")
        name.Size = UDim2.new(1, -16, 0, 32)
        name.Position = UDim2.fromOffset(8, 96)
        name.BackgroundTransparency = 1
        name.Text = def.name
        name.TextColor3 = Color3.fromRGB(255, 220, 120)
        name.Font = Enum.Font.GothamBold
        name.TextScaled = true
        name.ZIndex = 21
        name.Parent = card

        local desc = Instance.new("TextLabel")
        desc.Size = UDim2.new(1, -16, 0, 110)
        desc.Position = UDim2.fromOffset(8, 134)
        desc.BackgroundTransparency = 1
        desc.Text = def.desc
        desc.TextColor3 = Color3.new(1, 1, 1)
        desc.Font = Enum.Font.Gotham
        desc.TextSize = 13
        desc.TextWrapped = true
        desc.TextXAlignment = Enum.TextXAlignment.Center
        desc.TextYAlignment = Enum.TextYAlignment.Top
        desc.ZIndex = 21
        desc.Parent = card

        if def.cost then
            local cost = Instance.new("TextLabel")
            cost.Size = UDim2.new(1, -16, 0, 20)
            cost.Position = UDim2.new(0, 8, 1, -28)
            cost.BackgroundTransparency = 1
            cost.Text = def.cost
            cost.TextColor3 = Color3.fromRGB(255, 140, 140)
            cost.Font = Enum.Font.GothamBold
            cost.TextScaled = true
            cost.ZIndex = 21
            cost.Parent = card
        end

        local chosen = def  -- capture
        card.MouseButton1Click:Connect(function()
            if chosen.needsUnitTarget then
                -- Two-step: send initial CardChoice, server switches phase
                -- to unitTarget, then we show the target picker.
                pendingCardId = chosen.id
                remotes.CardChoice:FireServer({ cardId = chosen.id })
            else
                remotes.CardChoice:FireServer({ cardId = chosen.id })
            end
        end)
        card.Parent = cardRow
    end
end

local function collectTargetableUnits(state: any)
    -- Gather unit instances from bench + board so the player can pick which
    -- one to apply Tung Tung's Nap to. We use unitId as the key (see
    -- CardService rationale: a single unit id simplifies cross-combat
    -- tracking when the bench/board shuffles).
    local out = {}
    local seen = {}
    for _, u in pairs(state.bench or {}) do
        if u and not seen[u.unitId] then
            seen[u.unitId] = true
            table.insert(out, u)
        end
    end
    for _, u in ipairs(state.board or {}) do
        if not seen[u.unitId] then
            seen[u.unitId] = true
            table.insert(out, u)
        end
    end
    return out
end

local function renderTargetGrid(state: any)
    clearChildren(targetGrid)
    local candidates = collectTargetableUnits(state)

    if #candidates == 0 then
        local msg = Instance.new("TextLabel")
        msg.Size = UDim2.new(1, 0, 0, 40)
        msg.BackgroundTransparency = 1
        msg.Text = "No units yet -- pick one after buying."
        msg.TextColor3 = Color3.fromRGB(255, 140, 140)
        msg.Font = Enum.Font.GothamBold
        msg.TextScaled = true
        msg.ZIndex = 22
        msg.Parent = targetGrid
        return
    end

    for _, u in ipairs(candidates) do
        local def = UnitDefinitions[u.unitId]
        if not def then continue end
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.fromOffset(96, 110)
        btn.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
        btn.BorderSizePixel = 0
        btn.Text = ""
        btn.ZIndex = 22
        makeCorner(btn, 8)
        local rDef = RarityDefinitions[u.rarity]
        if rDef then
            local s = Instance.new("UIStroke")
            s.Color = rDef.color
            s.Thickness = 2
            s.Parent = btn
        end

        local em = Instance.new("TextLabel")
        em.Size = UDim2.new(1, 0, 0.7, 0)
        em.BackgroundTransparency = 1
        em.Text = def.emoji
        em.TextScaled = true
        em.Font = Enum.Font.GothamBlack
        em.TextColor3 = Color3.new(1, 1, 1)
        em.ZIndex = 23
        em.Parent = btn

        local nm = Instance.new("TextLabel")
        nm.Size = UDim2.new(1, 0, 0.3, 0)
        nm.Position = UDim2.fromScale(0, 0.7)
        nm.BackgroundTransparency = 1
        nm.Text = def.name
        nm.TextScaled = true
        nm.Font = Enum.Font.GothamBold
        nm.TextColor3 = Color3.new(1, 1, 1)
        nm.ZIndex = 23
        nm.Parent = btn

        local uid = u.unitId
        btn.MouseButton1Click:Connect(function()
            if pendingCardId then
                remotes.CardChoice:FireServer({ cardId = pendingCardId, targetUnitInstanceId = uid })
            end
        end)
        btn.Parent = targetGrid
    end
end

function CardDraftController.Init(deps)
    remotes = deps.Remotes
    local shared = ReplicatedStorage:WaitForChild("Shared")
    CardDefinitions = require(shared:WaitForChild("CardDefinitions"))
    UnitDefinitions = require(shared:WaitForChild("UnitDefinitions"))
    RarityDefinitions = require(shared:WaitForChild("RarityDefinitions"))

    local pg = player:WaitForChild("PlayerGui")
    local mainUI = pg:WaitForChild("MainUI", 5)
    if not mainUI then
        warn("[CardDraftController] MainUI not found")
        return
    end
    buildDraftModal(mainUI)
    buildTargetModal(mainUI)
end

function CardDraftController.Render(state: any)
    if not draftModal or not state then return end

    local showDraft = (state.phase == "eventDraft" or state.phase == "forgeDraft")
        and state.pendingDraft and state.pendingDraft.options

    if showDraft then
        renderCards(state.pendingDraft.options, state.pendingDraft.kind)
        draftModal.Visible = true
    else
        draftModal.Visible = false
    end

    local showTarget = state.phase == "unitTarget" and state.pendingTarget
    if showTarget then
        pendingCardId = state.pendingTarget.cardId
        local card = CardDefinitions.CARDS[pendingCardId]
        targetTitle.Text = card and ("Apply %s to:"):format(card.name) or "Pick a unit"
        renderTargetGrid(state)
        targetModal.Visible = true
    else
        targetModal.Visible = false
        if state.phase ~= "eventDraft" and state.phase ~= "forgeDraft" then
            pendingCardId = nil
        end
    end
end

return CardDraftController
