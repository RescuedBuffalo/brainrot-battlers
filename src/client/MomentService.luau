--!strict
-- Orchestrates stacked feedback layers around a "moment" (a specific ability
-- event in the combat stream). One public entry: play(name, context). All
-- visual layers are best-effort -- if a unit dies mid-moment or the camera
-- preset changes, layers degrade gracefully rather than getting stuck.
--
-- Layers, in the order they fire:
--   1. vignette       -- radial gradient tint over the whole screen
--   2. bigNumber      -- extra-large damage floater at target position
--   3. particleBurst  -- one-shot ParticleEmitter at context.position
--   4. cameraPunch    -- brief CFrame offset in direction
--   5. hitStop        -- freeze pivot-tween on the target model
--   6. timeDilation   -- visually elongate in-flight tweens (pure visual)
--   7. screenShake    -- randomized camera jitter
--   8. vo             -- voice bark via SoundController.PlayVO
--
-- Time dilation is a visual trick only. Server combat tick rate is
-- authoritative; we just slow-motion the CombatRenderer's render queue
-- pacing for durationMs then snap back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MomentService = {}

local player = Players.LocalPlayer
local MomentDefinitions
local CameraController
local SoundController
local CombatRenderer

local vignetteFrame: Frame?
-- Models frozen by hit-stop so we can unfreeze on timeout
local frozenModels: { [Model]: number } = {}  -- model -> unfreezeAt clock time
-- Global visual-time scale applied during time dilation
local timeScale = 1.0

-- ---------- public hooks ---------- --

-- CombatRenderer polls this before applying a pivot tween to see if the
-- target should be frozen. Implementation just checks the frozenModels map.
function MomentService.IsFrozen(model: Model): boolean
    local until_ = frozenModels[model]
    if not until_ then return false end
    if os.clock() >= until_ then
        frozenModels[model] = nil
        return false
    end
    return true
end

-- Visual time scale for CombatRenderer's tween durations.
function MomentService.TimeScale(): number
    return timeScale
end

-- ---------- layer implementations ---------- --

local function playVignette(layer)
    if not vignetteFrame then return end
    local durationSec = (layer.durationMs or 300) / 1000
    local alpha = layer.alpha or 0.5
    local color = layer.color or Color3.new(0, 0, 0)
    vignetteFrame.BackgroundColor3 = color
    vignetteFrame.BackgroundTransparency = 1
    vignetteFrame.Visible = true
    TweenService:Create(vignetteFrame, TweenInfo.new(durationSec * 0.3),
        { BackgroundTransparency = 1 - alpha }):Play()
    task.delay(durationSec * 0.4, function()
        if not vignetteFrame then return end
        local tween = TweenService:Create(vignetteFrame, TweenInfo.new(durationSec * 0.5),
            { BackgroundTransparency = 1 })
        tween:Play()
        tween.Completed:Connect(function()
            if vignetteFrame then vignetteFrame.Visible = false end
        end)
    end)
end

local function playBigNumber(layer, ctx)
    -- Reuses the existing damage floater pipeline -- spawn a BillboardGui with
    -- extra scale + color override. We piggyback on the target's Head.
    local model = ctx.targetModel
    if not model then return end
    local head = model:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then return end

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(220 * (layer.scale or 1.5), 80 * (layer.scale or 1.5))
    bb.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
    bb.AlwaysOnTop = true
    bb.Parent = head

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = ctx.amount and ("-%d!"):format(math.floor(ctx.amount)) or "💥"
    label.TextColor3 = layer.color or Color3.fromRGB(255, 220, 100)
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.Parent = bb

    task.spawn(function()
        local t0 = os.clock()
        local dur = 0.9
        while os.clock() - t0 < dur do
            local a = (os.clock() - t0) / dur
            bb.StudsOffsetWorldSpace = Vector3.new(0, 2.5 + a * 3, 0)
            label.TextTransparency = math.max(0, (a - 0.4) / 0.6)
            task.wait()
        end
        bb:Destroy()
    end)
end

local function playParticleBurst(layer, ctx)
    local position = ctx.position
    if not position then return end
    local anchor = Instance.new("Part")
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.Position = position
    anchor.Parent = Workspace

    local attach = Instance.new("Attachment")
    attach.Parent = anchor

    local pe = Instance.new("ParticleEmitter")
    pe.Rate = 0  -- one-shot only
    pe.Lifetime = NumberRange.new(0.8, 1.4)
    pe.Speed = NumberRange.new(8, 18)
    pe.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(1, 0.1),
    })
    pe.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    pe.Color = ColorSequence.new(layer.color or Color3.fromRGB(255, 160, 80))
    pe.Rotation = NumberRange.new(0, 360)
    pe.SpreadAngle = Vector2.new(180, 180)
    pe.LightEmission = 0.8
    pe.Acceleration = Vector3.new(0, -6, 0)
    pe.Parent = attach

    pe:Emit(layer.count or 30)

    task.delay(2.0, function()
        if anchor.Parent then anchor:Destroy() end
    end)
end

local function playCameraPunch(layer)
    if CameraController and CameraController.punch then
        CameraController.punch(
            layer.direction or Vector3.new(0, -1, 0),
            layer.intensity or 0.5,
            layer.durationMs or 200
        )
    end
end

local function playHitStop(layer, ctx)
    local model = ctx.targetModel
    if not model then return end
    local durationSec = (layer.targetMs or 80) / 1000
    frozenModels[model] = os.clock() + durationSec
end

local function playTimeDilation(layer)
    local durationSec = (layer.durationMs or 250) / 1000
    local factor = layer.factor or 0.5
    timeScale = factor
    task.delay(durationSec, function()
        -- Only clear if nothing else took over; more sophisticated stacking
        -- would need a counter, but for v1 this is enough.
        if timeScale == factor then timeScale = 1.0 end
    end)
end

local function playScreenShake(layer)
    if CameraController and CameraController.shake then
        CameraController.shake(layer.intensity or 0.5, layer.durationMs or 200)
    end
end

local function playVO(layer)
    if SoundController and SoundController.PlayVO and layer.name then
        SoundController.PlayVO(layer.name)
    end
end

-- ---------- dispatch ---------- --

local LAYER_ORDER = {
    "vignette", "bigNumber", "particleBurst", "cameraPunch",
    "hitStop", "timeDilation", "screenShake", "vo",
}

local LAYER_IMPLS = {
    vignette       = playVignette,
    bigNumber      = playBigNumber,
    particleBurst  = playParticleBurst,
    cameraPunch    = playCameraPunch,
    hitStop        = playHitStop,
    timeDilation   = playTimeDilation,
    screenShake    = playScreenShake,
    vo             = playVO,
}

-- ---------- public API ---------- --

function MomentService.Init(deps)
    MomentDefinitions = require(script.Parent:WaitForChild("MomentDefinitions"))
    CameraController = deps.CameraController
    SoundController = deps.SoundController
    CombatRenderer = deps.CombatRenderer

    -- Build the vignette once at boot -- reuses across every play().
    local pg = player:WaitForChild("PlayerGui")
    local screen = Instance.new("ScreenGui")
    screen.Name = "MomentOverlay"
    screen.IgnoreGuiInset = true
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 200
    screen.Parent = pg

    vignetteFrame = Instance.new("Frame")
    vignetteFrame.Name = "Vignette"
    vignetteFrame.Size = UDim2.fromScale(1, 1)
    vignetteFrame.BackgroundColor3 = Color3.new(0, 0, 0)
    vignetteFrame.BackgroundTransparency = 1
    vignetteFrame.BorderSizePixel = 0
    vignetteFrame.Visible = false
    vignetteFrame.ZIndex = 1
    vignetteFrame.Parent = screen

    -- Radial-ish gradient to make the edges tint more than the center
    local grad = Instance.new("UIGradient")
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1, 0),
    })
    grad.Rotation = 0
    grad.Parent = vignetteFrame
end

-- context: { sourceActorId, targetActorId, position, amount, targetModel, sourceModel }
-- NOTE on debugging: MomentService relies on module-local upvalues populated
-- by Init (MomentDefinitions, vignetteFrame, etc.). If you verify behavior
-- from Studio's command bar via execute_luau, remember that runs in a
-- SEPARATE VM from the LocalScripts -- that VM's copy of MomentService has
-- never had Init called, so play() silently early-returns here. Trigger
-- plays from a real client context (a CombatEvent, a KeyCode handler, or
-- a task.delay inside ClientMain) to exercise the actual code path.
function MomentService.play(name: string, context: any)
    if not MomentDefinitions then return end
    local def = MomentDefinitions.MOMENTS[name]
    if not def then return end  -- ability has no moment configured; skip silently

    for _, layerName in ipairs(LAYER_ORDER) do
        local layer = def[layerName]
        if layer then
            local impl = LAYER_IMPLS[layerName]
            if impl then
                local ok, err = pcall(impl, layer, context or {})
                if not ok then
                    warn(("[MomentService] layer '%s' error: %s"):format(layerName, tostring(err)))
                end
            end
        end
    end
end

return MomentService
