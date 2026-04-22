--!strict
-- Client boot. Wires UIController, CombatRenderer, Input. Subscribes
-- StateUpdate and CombatEvent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local script_ = script
local parentScripts = script_.Parent

local UIController    = require(parentScripts:WaitForChild("UIController"))
local CombatRenderer  = require(parentScripts:WaitForChild("CombatRenderer"))
local Input           = require(parentScripts:WaitForChild("Input"))
local SoundController = require(parentScripts:WaitForChild("SoundController"))
local CameraController = require(parentScripts:WaitForChild("CameraController"))
local Tutorial        = require(parentScripts:WaitForChild("Tutorial"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateUpdate  = remotes:WaitForChild("StateUpdate")
local combatEvent  = remotes:WaitForChild("CombatEvent")
local crateReveal  = remotes:WaitForChild("CrateReveal")

local deps = {
    Remotes = remotes,
    UIController = UIController,
    CombatRenderer = CombatRenderer,
    Input = Input,
    SoundController = SoundController,
    CameraController = CameraController,
    Tutorial = Tutorial,
}

SoundController.Init()
CameraController.Init()
Tutorial.Init()
UIController.Init(deps)
CombatRenderer.Init(deps)
Input.Init(deps)

-- Global click SFX: every TextButton / ImageButton in PlayerGui plays
-- "click" on MouseButton1Click. Cheap way to get auditory feedback on the
-- whole UI without threading SoundController through every handler.
local Players = game:GetService("Players")
local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
local function hookButton(inst: Instance)
    if inst:IsA("GuiButton") then
        inst.MouseButton1Click:Connect(function()
            SoundController.Play("click")
        end)
    end
end
for _, d in ipairs(pg:GetDescendants()) do hookButton(d) end
pg.DescendantAdded:Connect(hookButton)

local lastPhase: string? = nil

stateUpdate.OnClientEvent:Connect(function(state)
    UIController.Render(state)
    if state.phase ~= lastPhase then
        lastPhase = state.phase
        CameraController.SetPhase(state.phase)
        -- Phase-transition SFX
        if state.phase == "combat" then
            SoundController.Play("combat")
        elseif state.phase == "victory" then
            SoundController.Play("victory")
        elseif state.phase == "defeat" then
            SoundController.Play("defeat")
        end
    end
    -- First-run tutorial hook: starts on first state snapshot, advances
    -- as the player performs each step, persists completion to profile.
    Tutorial.Start(state)
    Tutorial.Tick(state)
end)

combatEvent.OnClientEvent:Connect(function(events)
    CombatRenderer.PlayEvents(events)
end)

crateReveal.OnClientEvent:Connect(function(drop)
    UIController.ShowCrateReveal(drop)
    SoundController.Play("crateOpen")
    if drop and drop.upgraded then
        task.delay(1.4, function() SoundController.Play("upgrade") end)
    end
end)

print("[Client] booted")
