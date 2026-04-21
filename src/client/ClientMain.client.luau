--!strict
-- Client boot. Wires UIController, CombatRenderer, Input. Subscribes
-- StateUpdate and CombatEvent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local script_ = script
local parentScripts = script_.Parent

local UIController    = require(parentScripts:WaitForChild("UIController"))
local CombatRenderer  = require(parentScripts:WaitForChild("CombatRenderer"))
local Input           = require(parentScripts:WaitForChild("Input"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateUpdate  = remotes:WaitForChild("StateUpdate")
local combatEvent  = remotes:WaitForChild("CombatEvent")

local deps = {
    Remotes = remotes,
    UIController = UIController,
    CombatRenderer = CombatRenderer,
    Input = Input,
}

UIController.Init(deps)
CombatRenderer.Init(deps)
Input.Init(deps)

stateUpdate.OnClientEvent:Connect(function(state)
    UIController.Render(state)
end)

combatEvent.OnClientEvent:Connect(function(events)
    CombatRenderer.PlayEvents(events)
end)

print("[Client] booted")
