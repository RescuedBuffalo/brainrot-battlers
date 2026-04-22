--!strict
-- Server boot. Wires services together, binds RemoteEvent handlers, and
-- relays Player lifecycle events to GameManager. Each service receives its
-- deps in Init so services don't reach into globals.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local serverFolder = ServerScriptService:WaitForChild("GameServer")
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")

local DataService    = require(serverFolder:WaitForChild("DataService"))
local UnitSpawner    = require(serverFolder:WaitForChild("UnitSpawner"))
local AbilityService = require(serverFolder:WaitForChild("AbilityService"))
local CombatEngine   = require(serverFolder:WaitForChild("CombatEngine"))
local ShopService    = require(serverFolder:WaitForChild("ShopService"))
local CrateService   = require(serverFolder:WaitForChild("CrateService"))
local LobbyService   = require(serverFolder:WaitForChild("LobbyService"))
local GameManager    = require(serverFolder:WaitForChild("GameManager"))

local deps = {
    DataService = DataService,
    UnitSpawner = UnitSpawner,
    AbilityService = AbilityService,
    CombatEngine = CombatEngine,
    ShopService = ShopService,
    CrateService = CrateService,
    LobbyService = LobbyService,
    GameManager = GameManager,
    Remotes = ReplicatedStorage:WaitForChild("Remotes"),
    Shared = sharedFolder,
}

DataService.Init()
UnitSpawner.Init(deps)
AbilityService.Init(deps)
CombatEngine.Init(deps)
ShopService.Init(deps)
CrateService.Init(deps)
LobbyService.Init(deps)
GameManager.Init(deps)

-- ---------- remote wiring ---------- --
-- All RemoteEvent handlers dispatch through GameManager. Server validates
-- every argument; clients are hostile by default.

local remotes = deps.Remotes

remotes.BuyUnit.OnServerEvent:Connect(function(player, slotIdx)
    GameManager.HandleBuyUnit(player, slotIdx)
end)

remotes.SellUnit.OnServerEvent:Connect(function(player, source, idx)
    GameManager.HandleSellUnit(player, source, idx)
end)

remotes.PlaceUnit.OnServerEvent:Connect(function(player, payload)
    GameManager.HandlePlaceUnit(player, payload)
end)

remotes.RerollShop.OnServerEvent:Connect(function(player)
    GameManager.HandleRerollShop(player)
end)

remotes.BuyXP.OnServerEvent:Connect(function(player)
    GameManager.HandleBuyXP(player)
end)

remotes.StartCombat.OnServerEvent:Connect(function(player)
    GameManager.HandleStartCombat(player)
end)

remotes.NextRound.OnServerEvent:Connect(function(player)
    GameManager.HandleNextRound(player)
end)

remotes.OpenCrate.OnServerEvent:Connect(function(player)
    GameManager.HandleOpenCrate(player)
end)

-- Sync request -- client can ask for its current state at any time (e.g. on
-- character respawn or UI refresh).
local getState = remotes:FindFirstChild("GetPlayerState")
if getState and getState:IsA("RemoteFunction") then
    getState.OnServerInvoke = function(player)
        local state = GameManager.GetState(player.UserId)
        return state
    end
end

Players.PlayerAdded:Connect(GameManager.OnPlayerAdded)
Players.PlayerRemoving:Connect(GameManager.OnPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
    GameManager.OnPlayerAdded(p)
end

print("[GameServer] booted")
