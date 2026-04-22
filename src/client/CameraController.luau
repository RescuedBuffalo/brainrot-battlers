--!strict
-- Phase-driven scripted camera. Three presets:
--   lobby  -- free camera (restore CameraType.Custom so the default follow
--             rig works; the player can walk around their hub)
--   shop   -- static tilted bird's-eye over the arena, wide enough to see
--             bench placements and the whole board
--   combat -- slow cinematic orbit around the arena center, subtle ~5deg
--             range so nothing gets motion-sick
--
-- Uses TweenService on a CFrameValue to drive Camera.CFrame so transitions
-- are smooth instead of snap cuts.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraController = {}

local camera = Workspace.CurrentCamera
local currentPhase: string? = nil
local orbitHeartbeat: RBXScriptConnection? = nil

-- Arena is centered at origin in world space (Phase 3 set ORIGIN = -10).
-- Lobby is at (-80, 40, 0). Pick views that frame those targets.
local ARENA_CENTER = Vector3.new(0, 0, 0)

local SHOP_CFRAME = CFrame.new(Vector3.new(0, 28, 22), ARENA_CENTER)
-- Combat orbit parameters: radius, height, period in seconds per rotation
local COMBAT_RADIUS = 30
local COMBAT_HEIGHT = 16
local COMBAT_PERIOD = 40  -- slow circle

local function stopOrbit()
    if orbitHeartbeat then
        orbitHeartbeat:Disconnect()
        orbitHeartbeat = nil
    end
end

-- Tween the camera to a target CFrame by driving a CFrameValue. Doing it
-- this way instead of RunService-stepped lerps keeps the movement smooth
-- through frame hitches.
local function tweenTo(target: CFrame, duration: number)
    stopOrbit()
    local holder = Instance.new("CFrameValue")
    holder.Value = camera.CFrame
    local conn = holder:GetPropertyChangedSignal("Value"):Connect(function()
        camera.CFrame = holder.Value
    end)
    local tween = TweenService:Create(
        holder,
        TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Value = target }
    )
    tween.Completed:Connect(function()
        conn:Disconnect()
        holder:Destroy()
    end)
    tween:Play()
end

-- Start a smooth orbit that continues past the tween. Called after the
-- combat-entry tween so the transition is: current → orbit start → orbit loop.
local function startOrbit()
    stopOrbit()
    local t0 = os.clock()
    orbitHeartbeat = RunService.Heartbeat:Connect(function()
        local elapsed = os.clock() - t0
        local angle = (elapsed / COMBAT_PERIOD) * math.pi * 2
        local pos = ARENA_CENTER + Vector3.new(
            math.sin(angle) * COMBAT_RADIUS,
            COMBAT_HEIGHT,
            math.cos(angle) * COMBAT_RADIUS
        )
        camera.CFrame = CFrame.new(pos, ARENA_CENTER)
    end)
end

local function enterLobby()
    stopOrbit()
    -- Restore default follow camera. We reset to Custom not Fixed so the
    -- player's character rig drives it.
    camera.CameraType = Enum.CameraType.Custom
end

local function enterShop()
    camera.CameraType = Enum.CameraType.Scriptable
    tweenTo(SHOP_CFRAME, 0.8)
end

local function enterCombat()
    camera.CameraType = Enum.CameraType.Scriptable
    -- Start orbit from the current entry CFrame (initial position is derived
    -- from angle 0 which places the camera in front of the arena).
    local startPos = ARENA_CENTER + Vector3.new(
        math.sin(0) * COMBAT_RADIUS,
        COMBAT_HEIGHT,
        math.cos(0) * COMBAT_RADIUS
    )
    tweenTo(CFrame.new(startPos, ARENA_CENTER), 0.8)
    task.delay(0.8, function()
        if currentPhase == "combat" then
            startOrbit()
        end
    end)
end

function CameraController.Init()
    camera = Workspace.CurrentCamera
    -- Default to lobby view; StateUpdate will override once the server pushes
    -- a phase.
    enterLobby()
    currentPhase = "lobby"

    -- Guard against CurrentCamera being reassigned by Roblox (e.g. on
    -- character respawn). Reattach + reapply preset.
    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        camera = Workspace.CurrentCamera
        if currentPhase then
            CameraController.SetPhase(currentPhase, true)
        end
    end)

    -- Reapply on character respawn: the Humanoid sets CameraType=Custom as
    -- part of its default controller, which blows away our Scriptable for
    -- shop/combat phases.
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    if player then
        local function onCharacter()
            task.wait(0.3)
            if currentPhase then
                CameraController.SetPhase(currentPhase, true)
            end
        end
        if player.Character then onCharacter() end
        player.CharacterAdded:Connect(onCharacter)
    end
end

-- Force = true re-applies the preset even if the phase hasn't changed;
-- used when Roblox resets CameraType on character respawn.
function CameraController.SetPhase(phase: string, force: boolean?)
    if phase == currentPhase and not force then return end
    currentPhase = phase

    if phase == "shop" or phase == "postcombat" then
        enterShop()
    elseif phase == "combat" then
        enterCombat()
    else
        enterLobby()
    end
end

return CameraController
