--!strict
-- Slay-the-Spire style node map generator. Shared between server (owns the
-- authoritative map and validates picks) and client (renders the map UI).
--
-- A map is a list of nodes organized in layers: layer 1 is the fixed starting
-- Combat, layer N is the fixed Boss, intermediate layers have 1-3 nodes with
-- 2-3 branching edges into the next layer. The map is a DAG.
--
-- The generator is pure and deterministic given a seed: same seed produces
-- the same map, so a player rejoining can't re-roll for a better map.

local RunMap = {}

export type NodeType = "combat" | "elite" | "shop" | "event" | "forge" | "boss"
export type NodeId = string

export type Node = {
    id: NodeId,
    type: NodeType,
    layer: number,
    column: number,        -- 0..2 within the layer (for UI positioning)
    nextNodeIds: { NodeId },
    payload: { any },      -- type-specific: for combat, { enemyRound = N, elite = bool }
    visited: boolean,      -- set true after this node is resolved
}

export type Map = {
    seed: number,
    nodes: { [NodeId]: Node },
    startNodeId: NodeId,
    bossNodeId: NodeId,
    layerCount: number,
}

-- v1 shape: 9 layers total (1 fixed start combat, 7 mid-layers, 1 boss).
-- Width per middle layer alternates to give a nice silhouette.
local LAYER_COUNT = 9
local MIDDLE_WIDTHS = { 2, 3, 2, 3, 2, 3, 2 }  -- 7 entries -> layers 2..8

-- Weighted pool for middle-layer node types. Keyed percentages sum to 100.
-- Elite slots are reserved explicitly (one guaranteed somewhere in layers 5-7)
-- to avoid random bias leaving them out.
local WEIGHTS = {
    combat = 40,
    shop   = 18,
    event  = 18,
    forge  = 18,
    elite  = 6,
}

-- Minimum guarantees so every run has texture. If the RNG misses any of these,
-- we force-replace one Combat node in a safe layer with the missing type.
local REQUIRED_TYPES = { "shop", "event", "forge", "elite" }

-- Enemy round pool for Combat nodes. Picks from the 10 existing EnemyRounds
-- (skipping the Boss entry at index 10 which is used only for the final node).
-- Tagged by difficulty band so we can stagger them across the map.
local COMBAT_POOL = {
    easy   = { 1, 2 },
    medium = { 3, 4, 6 },
    hard   = { 5, 7, 8, 9 },
}

local ELITE_POOL = { 5, 7, 8 }  -- harder rounds promoted to elite encounters

local BOSS_ROUND = 10

-- ---------- PRNG ---------- --
-- Lua's math.random is state-dependent across the VM; using a local linear
-- congruential generator keeps generation deterministic per seed.

local function makeRng(seed: number)
    local state = seed
    return function(n: number?)
        state = (state * 1103515245 + 12345) % 2147483648
        if n then
            return (state % n) + 1
        end
        return state / 2147483648
    end
end

-- ---------- helpers ---------- --

local function pickWeighted(rng, weights: { [string]: number }): string
    local total = 0
    for _, w in pairs(weights) do total += w end
    local roll = rng() * total
    local acc = 0
    for k, w in pairs(weights) do
        acc += w
        if roll <= acc then return k end
    end
    -- fallback
    for k in pairs(weights) do return k end
    return "combat"
end

local function nodeIdFor(layer: number, col: number): NodeId
    return ("L%d_C%d"):format(layer, col)
end

local function difficultyForLayer(layer: number): string
    if layer <= 3 then return "easy"
    elseif layer <= 6 then return "medium"
    else return "hard" end
end

local function pickFromList(rng, list)
    return list[rng(#list)]
end

-- ---------- generator ---------- --

-- Generate a DAG with `layerCount` layers, 2-3 nodes in middles, and edges
-- from each node to 1-2 in the next layer. Uses greedy adjacency: walk
-- layer-by-layer connecting each node to 1 or 2 consecutive columns in the
-- next layer so the graph is planar (no crossings) and each next-layer node
-- is reachable.
function RunMap.generate(seed: number): Map
    seed = seed or os.time()
    local rng = makeRng(seed)

    local nodes: { [NodeId]: Node } = {}

    -- Layer 1: single Combat node
    local startId = nodeIdFor(1, 0)
    nodes[startId] = {
        id = startId, type = "combat", layer = 1, column = 1, nextNodeIds = {},
        payload = { enemyRound = pickFromList(rng, COMBAT_POOL.easy), elite = false },
        visited = false,
    }

    -- Middle layers 2..8
    local prevLayerIds = { startId }
    for i, width in ipairs(MIDDLE_WIDTHS) do
        local layer = i + 1  -- 2..8
        local layerIds = {}
        -- Spread columns evenly: column index in 0..2 so UI can position.
        for col = 0, width - 1 do
            local id = nodeIdFor(layer, col)
            local nodeType = pickWeighted(rng, WEIGHTS)
            local payload = {}
            if nodeType == "combat" then
                payload.enemyRound = pickFromList(rng, COMBAT_POOL[difficultyForLayer(layer)])
                payload.elite = false
            elseif nodeType == "elite" then
                payload.enemyRound = pickFromList(rng, ELITE_POOL)
                payload.elite = true
                payload.guaranteedCrate = "rare"
            end
            nodes[id] = {
                id = id, type = nodeType, layer = layer, column = col,
                nextNodeIds = {}, payload = payload, visited = false,
            }
            table.insert(layerIds, id)
        end

        -- Wire edges from prev layer to this one. Each prev node connects to
        -- 1-2 nodes in this layer, biased toward its own column so the map
        -- stays planar. Every node in this layer must receive at least one
        -- incoming edge.
        local received = {}  -- set of this-layer ids that got an incoming edge
        for _, prevId in ipairs(prevLayerIds) do
            local prev = nodes[prevId]
            -- Map prev column into this layer's column range
            local prevCol = prev.column
            local choices = {}
            for col = 0, width - 1 do
                if math.abs(col - prevCol) <= 1 then
                    table.insert(choices, layerIds[col + 1])
                end
            end
            if #choices == 0 then
                choices = { layerIds[math.min(width, math.max(1, prevCol + 1))] }
            end
            local pick1 = choices[rng(#choices)]
            table.insert(prev.nextNodeIds, pick1)
            received[pick1] = true
            -- 50% chance of a second edge if there's another choice
            if #choices > 1 and rng() < 0.5 then
                local others = {}
                for _, c in ipairs(choices) do if c ~= pick1 then table.insert(others, c) end end
                if #others > 0 then
                    local pick2 = others[rng(#others)]
                    table.insert(prev.nextNodeIds, pick2)
                    received[pick2] = true
                end
            end
        end

        -- Cover any layer node that missed an incoming edge by attaching one
        -- from the nearest prev-layer node.
        for _, id in ipairs(layerIds) do
            if not received[id] then
                local n = nodes[id]
                local bestPrev, bestDist = prevLayerIds[1], math.huge
                for _, pid in ipairs(prevLayerIds) do
                    local d = math.abs(nodes[pid].column - n.column)
                    if d < bestDist then bestDist = d; bestPrev = pid end
                end
                table.insert(nodes[bestPrev].nextNodeIds, id)
            end
        end

        prevLayerIds = layerIds
    end

    -- Final layer: Boss node, single column
    local bossId = nodeIdFor(LAYER_COUNT, 0)
    nodes[bossId] = {
        id = bossId, type = "boss", layer = LAYER_COUNT, column = 1, nextNodeIds = {},
        payload = { enemyRound = BOSS_ROUND, elite = true },
        visited = false,
    }
    for _, prevId in ipairs(prevLayerIds) do
        table.insert(nodes[prevId].nextNodeIds, bossId)
    end

    -- Guarantee variety: for each REQUIRED_TYPE, if absent, convert one
    -- Combat node in a middle layer into that type. Skip layer 2 so the
    -- opening stays predictable.
    local typeCounts: { [string]: number } = {}
    for _, n in pairs(nodes) do
        typeCounts[n.type] = (typeCounts[n.type] or 0) + 1
    end
    for _, req in ipairs(REQUIRED_TYPES) do
        if not typeCounts[req] or typeCounts[req] == 0 then
            -- Find a swap candidate: any Combat node in layers 3..8
            for _, n in pairs(nodes) do
                if n.type == "combat" and n.layer >= 3 and n.layer <= 8 then
                    n.type = req
                    n.payload = {}
                    if req == "elite" then
                        n.payload.enemyRound = pickFromList(rng, ELITE_POOL)
                        n.payload.elite = true
                        n.payload.guaranteedCrate = "rare"
                    end
                    break
                end
            end
        end
    end

    return {
        seed = seed,
        nodes = nodes,
        startNodeId = startId,
        bossNodeId = bossId,
        layerCount = LAYER_COUNT,
    }
end

-- Serialization helpers -- Maps are plain data so they replicate fine over
-- RemoteEvents, but we still expose these for sanity checks.
function RunMap.nodeCount(map: Map): number
    local n = 0
    for _ in pairs(map.nodes) do n += 1 end
    return n
end

function RunMap.isAdjacent(map: Map, fromId: NodeId, toId: NodeId): boolean
    local from = map.nodes[fromId]
    if not from then return false end
    for _, id in ipairs(from.nextNodeIds) do
        if id == toId then return true end
    end
    return false
end

return RunMap
