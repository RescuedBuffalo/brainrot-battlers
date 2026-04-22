--!strict
-- Thin wrapper around RunMap.generate. Owns no state itself -- the map is
-- stored directly on the player's PlayerState and persisted via DataService.
-- This module's job is validation + adjacency checks that GameManager
-- delegates to when the client sends SelectNextNode.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunMapService = {}

local RunMap

function RunMapService.Init(deps)
    local shared = deps.Shared
    RunMap = require(shared:WaitForChild("RunMap"))
end

-- Create a fresh map for a new run.
function RunMapService.NewMap(seed: number?)
    seed = seed or math.random(1, 2 ^ 31 - 1)
    return RunMap.generate(seed)
end

-- Returns the Node table for the player's currentNodeId, or nil.
function RunMapService.CurrentNode(state)
    if not state or not state.runMap or not state.currentNodeId then return nil end
    return state.runMap.nodes[state.currentNodeId]
end

-- Validate + advance. Returns true if the pick was legal and state.currentNodeId
-- has been updated, false otherwise.
function RunMapService.SelectNext(state, targetNodeId: string): boolean
    if not state or not state.runMap then return false end
    local map = state.runMap
    local current = map.nodes[state.currentNodeId]
    if not current then return false end
    if not current.visited then
        -- Can't advance until the current node is actually completed.
        return false
    end
    local legal = false
    for _, id in ipairs(current.nextNodeIds) do
        if id == targetNodeId then legal = true; break end
    end
    if not legal then return false end
    state.currentNodeId = targetNodeId
    return true
end

-- Mark the current node completed; called by GameManager after a combat
-- resolves or a card/shop interaction finishes.
function RunMapService.MarkCurrentVisited(state)
    local node = RunMapService.CurrentNode(state)
    if node then node.visited = true end
end

-- Boss completion = run end. Used by GameManager to distinguish the "advance"
-- case from the "victory" case.
function RunMapService.IsBossComplete(state): boolean
    if not state or not state.runMap then return false end
    local boss = state.runMap.nodes[state.runMap.bossNodeId]
    return boss and boss.visited or false
end

return RunMapService
