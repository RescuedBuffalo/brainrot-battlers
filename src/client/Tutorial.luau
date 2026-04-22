--!strict
-- First-run tutorial overlay. Three tips, each auto-advances when the
-- player does the corresponding action:
--   1. Buy a unit from the shop
--   2. Place it on the board (bench -> tile tap)
--   3. Hit FIGHT
--
-- Completion flag lives on the DataService profile (client sees it via the
-- state snapshot). Tutorial self-skips for returning players.
--
-- Rendering: a high-ZIndex ScreenGui with a pulsing arrow/label pointing at
-- the target UI element. The overlay is non-blocking (IgnoreGuiInset + no
-- background) so the player can still interact underneath.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Tutorial = {}

local player = Players.LocalPlayer

type Step = {
    id: string,
    message: string,
    targetPath: () -> GuiObject?,  -- returns the UI element the arrow should point at, or nil
    advanceOn: string,             -- state-field change that advances ("bench_has_unit", etc.)
}

-- Predicates read the StateUpdate snapshot; each returns true when its
-- corresponding action has been performed and the tutorial should advance.
local function benchHasUnit(state): boolean
    for _, b in pairs(state.bench or {}) do
        if b then return true end
    end
    return false
end

local function boardHasUnit(state): boolean
    return state.board and #state.board >= 1
end

local function combatStarted(state): boolean
    return state.phase == "combat" or state.phase == "postcombat" or state.phase == "victory"
end

local STEPS: { Step } = {
    {
        id = "buy",
        message = "👉 Tap a shop slot to buy your first unit",
        targetPath = function(): GuiObject?
            local pg = player:FindFirstChildOfClass("PlayerGui")
            local gui = pg and pg:FindFirstChild("MainUI")
            local shop = gui and gui:FindFirstChild("Shop")
            if shop then
                for _, child in ipairs(shop:GetChildren()) do
                    if child:IsA("TextButton") and child.LayoutOrder and child.LayoutOrder >= 1 and child.LayoutOrder <= 5 then
                        return child :: any
                    end
                end
            end
            return nil
        end,
        advanceOn = "",
    },
    {
        id = "place",
        message = "👉 Tap your bench unit, then tap a blue tile",
        targetPath = function(): GuiObject?
            local pg = player:FindFirstChildOfClass("PlayerGui")
            local gui = pg and pg:FindFirstChild("MainUI")
            local bench = gui and gui:FindFirstChild("Bench")
            return bench :: any
        end,
        advanceOn = "",
    },
    {
        id = "fight",
        message = "⚔️ Hit FIGHT to start combat!",
        targetPath = function(): GuiObject?
            local pg = player:FindFirstChildOfClass("PlayerGui")
            local gui = pg and pg:FindFirstChild("MainUI")
            local shop = gui and gui:FindFirstChild("Shop")
            if shop then
                for _, child in ipairs(shop:GetChildren()) do
                    if child:IsA("TextButton") and child.LayoutOrder == 100 then
                        return child :: any  -- FIGHT button has LayoutOrder = 100
                    end
                end
            end
            return nil
        end,
        advanceOn = "",
    },
}

-- Precompute predicates list, lined up with STEPS
local ADVANCE_CHECKS = {
    benchHasUnit,
    boardHasUnit,
    combatStarted,
}

local overlay: ScreenGui
local messageFrame: Frame
local messageLabel: TextLabel
local arrow: ImageLabel
local currentStepIdx: number = 0
local active = false

local function buildOverlay()
    overlay = Instance.new("ScreenGui")
    overlay.Name = "TutorialOverlay"
    overlay.IgnoreGuiInset = true
    overlay.ResetOnSpawn = false
    overlay.DisplayOrder = 100
    overlay.Enabled = false
    overlay.Parent = player:WaitForChild("PlayerGui")

    messageFrame = Instance.new("Frame")
    messageFrame.Name = "Message"
    messageFrame.AnchorPoint = Vector2.new(0.5, 0)
    messageFrame.Position = UDim2.new(0.5, 0, 0, 110)
    messageFrame.Size = UDim2.fromOffset(500, 60)
    messageFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    messageFrame.BackgroundTransparency = 0.15
    messageFrame.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = messageFrame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 220, 120)
    stroke.Thickness = 3
    stroke.Parent = messageFrame
    messageFrame.Parent = overlay

    messageLabel = Instance.new("TextLabel")
    messageLabel.Size = UDim2.new(1, -20, 1, -10)
    messageLabel.Position = UDim2.fromOffset(10, 5)
    messageLabel.BackgroundTransparency = 1
    messageLabel.TextColor3 = Color3.fromRGB(255, 240, 180)
    messageLabel.Font = Enum.Font.GothamBold
    messageLabel.TextScaled = true
    messageLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    messageLabel.TextStrokeTransparency = 0
    messageLabel.Text = ""
    messageLabel.Parent = messageFrame

    -- Simple bouncing text label used as the arrow indicator. A proper arrow
    -- image would need an asset; a bouncing "▼" is readable enough for MVP.
    arrow = Instance.new("TextLabel") :: any
    arrow.Name = "Arrow"
    arrow.AnchorPoint = Vector2.new(0.5, 1)
    arrow.Size = UDim2.fromOffset(80, 80)
    arrow.BackgroundTransparency = 1
    arrow.Text = "⬇"
    arrow.TextScaled = true
    arrow.TextColor3 = Color3.fromRGB(255, 220, 120)
    arrow.TextStrokeColor3 = Color3.new(0, 0, 0)
    arrow.TextStrokeTransparency = 0
    arrow.Font = Enum.Font.GothamBlack
    arrow.Parent = overlay
end

-- Re-anchor the arrow above the current target each frame. If the target
-- is missing (UI not yet built), hide the arrow.
local function updateArrow()
    if currentStepIdx < 1 or currentStepIdx > #STEPS then
        arrow.Visible = false
        return
    end
    local step = STEPS[currentStepIdx]
    local target = step.targetPath()
    if not target then
        arrow.Visible = false
        return
    end
    local absPos = target.AbsolutePosition
    local absSize = target.AbsoluteSize
    arrow.Visible = true
    arrow.Position = UDim2.fromOffset(absPos.X + absSize.X / 2, absPos.Y - 6)
end

local function startArrowLoop()
    RunService.Heartbeat:Connect(function()
        if not active then return end
        updateArrow()
    end)

    -- Subtle vertical bob on the arrow
    task.spawn(function()
        local t0 = os.clock()
        while true do
            if active and arrow.Visible then
                local bob = math.sin((os.clock() - t0) * 4) * 6
                arrow.Size = UDim2.fromOffset(80, 80 + bob)
            end
            task.wait()
        end
    end)
end

local function showStep(idx: number)
    if idx > #STEPS then
        Tutorial.Finish()
        return
    end
    currentStepIdx = idx
    messageLabel.Text = STEPS[idx].message
    overlay.Enabled = true
    active = true
end

function Tutorial.Init()
    buildOverlay()
    startArrowLoop()
end

-- Called with every StateUpdate. Checks whether the current step's advance
-- predicate is met and bumps forward if so.
function Tutorial.Tick(state)
    if not active then return end
    if currentStepIdx < 1 then return end

    local check = ADVANCE_CHECKS[currentStepIdx]
    if check and check(state) then
        showStep(currentStepIdx + 1)
    end
end

-- Client entry point: call Start() if the player hasn't completed the
-- tutorial yet (profile flag). Idempotent.
function Tutorial.Start(state)
    if state and state.tutorialDone then
        return
    end
    if active then return end
    showStep(1)
end

function Tutorial.Finish()
    active = false
    overlay.Enabled = false
end

function Tutorial.IsActive(): boolean
    return active
end

return Tutorial
