--!strict
-- Replays the server's CombatEvent stream as visual effects.
-- Protocol: PlayEvents(payload) where payload = {
--     events = {CombatEvent, ...},
--     result = {outcome, ticks},
-- }
-- Events are grouped by tick and played one group per TICK_RATE so the client
-- sees the same timing as the server's authoritative fight.
--
-- Actor -> Model mapping is read from the "ActorId" attribute the server sets
-- on each spawned unit. If replication hasn't caught up yet, PlayEvents waits
-- up to 1s before giving up on a given actor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local UnitDefinitions = require(sharedFolder:WaitForChild("UnitDefinitions"))

-- MomentService is required lazily via Init(deps) to avoid a require-time
-- dependency (CombatRenderer is referenced by MomentService too).
local MomentService

-- Slugify an ability name into the MomentDefinitions key format:
--   "Shadow Leap" -> "shadow_leap"
-- Cached because it's called in the combat hot path.
local slugCache: {[string]: string} = {}
local function abilitySlug(abilityName: string): string
    local cached = slugCache[abilityName]
    if cached then return cached end
    local s = abilityName:lower():gsub(" ", "_")
    slugCache[abilityName] = s
    return s
end

-- Build the full moment key from a source unit's unitId. Returns nil if
-- the unit doesn't exist in UnitDefinitions or has no ability name.
local function momentKeyFor(unitId: string): string?
    local def = UnitDefinitions[unitId]
    if not def or not def.abilityName then return nil end
    return unitId .. "_" .. abilitySlug(def.abilityName)
end

local CombatRenderer = {}

local TILE_W = 4
local TILE_D = 4
local TILE_H = 0.4
local COLS = Constants.COLS
local ROWS = Constants.ROWS
local ORIGIN_X = -(COLS * TILE_W) / 2 + TILE_W / 2
local ORIGIN_Z = -(ROWS * TILE_D) / 2 + TILE_D / 2
local PIVOT_LIFT = 0.5
local TICK_RATE = Constants.TICK_RATE

local function tileToWorld(x: number, y: number): Vector3
    return Vector3.new(ORIGIN_X + x * TILE_W, TILE_H + PIVOT_LIFT, ORIGIN_Z + y * TILE_D)
end

local actorModels: {[number]: Model} = {}
local currentPlayback: thread? = nil

local function scanActors()
    actorModels = {}
    local arena = Workspace:FindFirstChild("BattleArena")
    if not arena then return end
    for _, folderName in ipairs({"PlayerSide", "EnemySide"}) do
        local f = arena:FindFirstChild(folderName)
        if f then
            for _, m in ipairs(f:GetChildren()) do
                if m:IsA("Model") then
                    local id = m:GetAttribute("ActorId")
                    if type(id) == "number" then
                        actorModels[id] = m
                    end
                end
            end
        end
    end
end

local function facingYaw(model: Model): number
    return (model:GetAttribute("Side") == "enemy") and math.pi or 0
end

-- Pivot-tween by animating a CFrameValue and mirroring to the model pivot.
-- Cheaper than per-frame pivot updates in script and survives Heartbeat hitches.
local function tweenPivot(model: Model, targetCFrame: CFrame, duration: number)
    if not model.PrimaryPart then return end

    -- Phase 12: if the target is in hit-stop, skip the pivot tween entirely
    -- for the duration of the freeze. The next move event will start a fresh
    -- tween post-thaw.
    if MomentService and MomentService.IsFrozen and MomentService.IsFrozen(model) then
        return
    end

    -- Phase 12: visual time dilation. Stretch duration so slow-mo layers
    -- see a proportionally-longer animation; normal speed = 1.0.
    if MomentService and MomentService.TimeScale then
        local scale = MomentService.TimeScale()
        if scale > 0 and scale < 1 then
            duration = duration / scale
        end
    end

    local startCF = model:GetPivot()
    local holder = Instance.new("CFrameValue")
    holder.Value = startCF
    local conn = holder:GetPropertyChangedSignal("Value"):Connect(function()
        if model.Parent then
            model:PivotTo(holder.Value)
        end
    end)
    local tween = TweenService:Create(
        holder,
        TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Value = targetCFrame }
    )
    tween.Completed:Connect(function()
        conn:Disconnect()
        holder:Destroy()
    end)
    tween:Play()
end

local function spawnDamageNumber(targetModel: Model, amount: number, crit: boolean)
    local head = targetModel:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then return end

    local bb = Instance.new("BillboardGui")
    bb.Name = "DamageFloater"
    bb.Size = UDim2.fromOffset(110, 34)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
    bb.AlwaysOnTop = true
    bb.Parent = head

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Text = ("-%d"):format(math.floor(amount))
    label.TextColor3 = crit and Color3.fromRGB(255, 220, 100) or Color3.fromRGB(255, 235, 235)
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.Parent = label.Parent and nil or bb
    label.Parent = bb

    task.spawn(function()
        local t0 = os.clock()
        local dur = 0.55
        while os.clock() - t0 < dur do
            local a = (os.clock() - t0) / dur
            bb.StudsOffsetWorldSpace = Vector3.new(0, 2 + a * 1.6, 0)
            label.TextTransparency = a
            label.TextStrokeTransparency = a * 0.5 + 0.0
            task.wait()
        end
        bb:Destroy()
    end)
end

local function flashHit(model: Model)
    local hl = Instance.new("Highlight")
    hl.Name = "HitFlash"
    hl.FillColor = Color3.fromRGB(255, 180, 180)
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 1
    hl.Parent = model
    task.delay(TICK_RATE * Constants.HIT_FLASH_TICKS, function()
        if hl then hl:Destroy() end
    end)
end

local function flashAbility(model: Model)
    local hl = Instance.new("Highlight")
    hl.Name = "AbilityFlash"
    hl.FillColor = Color3.fromRGB(255, 240, 160)
    hl.FillTransparency = 0.2
    hl.OutlineColor = Color3.fromRGB(255, 255, 120)
    hl.OutlineTransparency = 0
    hl.Parent = model
    task.delay(TICK_RATE * Constants.ABILITY_FLASH_TICKS, function()
        if hl then hl:Destroy() end
    end)
end

local function spawnProjectile(fromHead: BasePart, toHead: BasePart)
    local p = Instance.new("Part")
    p.Name = "Projectile"
    p.Shape = Enum.PartType.Ball
    p.Size = Vector3.new(0.5, 0.5, 0.5)
    p.Color = Color3.fromRGB(255, 210, 80)
    p.Material = Enum.Material.Neon
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.Position = fromHead.Position
    p.Parent = Workspace

    local light = Instance.new("PointLight")
    light.Color = p.Color
    light.Range = 6
    light.Brightness = 2
    light.Parent = p

    local tween = TweenService:Create(
        p,
        TweenInfo.new(TICK_RATE * 0.8, Enum.EasingStyle.Linear),
        { Position = toHead.Position }
    )
    tween.Completed:Connect(function() p:Destroy() end)
    tween:Play()
end

local function spawnAoeRing(center: Vector3, radius: number, color: Color3)
    local ring = Instance.new("Part")
    ring.Name = "AoeRing"
    ring.Shape = Enum.PartType.Cylinder
    ring.Orientation = Vector3.new(0, 0, 90)
    ring.Size = Vector3.new(0.15, 1, 1)
    ring.Position = center - Vector3.new(0, 0.3, 0)
    ring.Color = color
    ring.Material = Enum.Material.Neon
    ring.Transparency = 0.15
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.Parent = Workspace
    local finalDiam = radius * 2 * TILE_W
    local tween = TweenService:Create(
        ring,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Size = Vector3.new(0.15, finalDiam, finalDiam),
            Transparency = 1,
        }
    )
    tween.Completed:Connect(function() ring:Destroy() end)
    tween:Play()
end

-- ---------- event handlers ---------- --

local handlers: {[string]: (evt: any) -> ()} = {}

handlers.move = function(evt)
    local model = actorModels[evt.source]
    if not model or not evt.to then return end
    local to = evt.to
    local pos = tileToWorld(to[1], to[2])
    local dur = evt.teleport and 0.12 or TICK_RATE * 0.9
    tweenPivot(model, CFrame.new(pos) * CFrame.Angles(0, facingYaw(model), 0), dur)
    model:SetAttribute("TileX", to[1])
    model:SetAttribute("TileY", to[2])
end

handlers.dmg = function(evt)
    local tgt = actorModels[evt.target]
    if not tgt then return end
    spawnDamageNumber(tgt, evt.amount, evt.crit)
    flashHit(tgt)
    if evt.hp ~= nil then
        tgt:SetAttribute("HP", evt.hp)
    end
end

handlers.ability = function(evt)
    local m = actorModels[evt.source]
    if m then flashAbility(m) end

    -- Phase 12: fire a Moment if this unit's ability has one defined.
    -- Moment key is "<unitId>_<abilitySlug>" so abilities can be moment-ified
    -- individually when a unit gets multiple abilities in future phases.
    if MomentService and m then
        local unitId = m:GetAttribute("UnitId")
        if unitId then
            local key = momentKeyFor(unitId)
            if key then
                MomentService.play(key, {
                    sourceActorId = evt.source,
                    sourceModel = m,
                    targetActorId = nil,
                    targetModel = nil,
                    position = m:GetPivot().Position,
                })
            end
        end
    end
end

handlers.shoot = function(evt)
    local src = actorModels[evt.source]
    local tgt = actorModels[evt.target]
    if not src or not tgt then return end
    local sh = src:FindFirstChild("Head")
    local th = tgt:FindFirstChild("Head")
    if not (sh and th and sh:IsA("BasePart") and th:IsA("BasePart")) then return end
    spawnProjectile(sh, th)
end

handlers.aoe = function(evt)
    local c = evt.center or {0, 0}
    local center = tileToWorld(c[1], c[2])
    local radius = evt.radius or (evt.global and math.max(COLS, ROWS) or 2)
    local color = evt.global and Color3.fromRGB(230, 100, 255) or Color3.fromRGB(255, 150, 100)
    spawnAoeRing(center, radius, color)
end

handlers.death = function(evt)
    local m = actorModels[evt.target]
    if not m then return end
    actorModels[evt.target] = nil
    task.delay(TICK_RATE * 0.5, function()
        if not m.Parent then return end
        local t0 = os.clock()
        local dur = 0.45
        while os.clock() - t0 < dur do
            local a = 1 - (os.clock() - t0) / dur
            if m.Parent then m:ScaleTo(math.max(0.01, a)) end
            task.wait()
        end
        if m.Parent then m:Destroy() end
    end)
end

handlers.shield = function(evt)
    local m = actorModels[evt.target]
    if not m then return end
    local hl = Instance.new("Highlight")
    hl.Name = "ShieldFlash"
    hl.FillColor = Color3.fromRGB(130, 200, 255)
    hl.FillTransparency = 0.4
    hl.OutlineColor = Color3.fromRGB(180, 220, 255)
    hl.OutlineTransparency = 0
    hl.Parent = m
    task.delay(0.6, function() if hl then hl:Destroy() end end)
end

handlers.stun = function(evt)
    local m = actorModels[evt.target]
    if not m then return end
    local head = m:FindFirstChild("Head")
    if not (head and head:IsA("BasePart")) then return end
    local bb = Instance.new("BillboardGui")
    bb.Name = "StunIcon"
    bb.Size = UDim2.fromOffset(40, 40)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
    bb.AlwaysOnTop = true
    bb.Parent = head
    local label = Instance.new("TextLabel")
    label.Text = "✨"
    label.BackgroundTransparency = 1
    label.TextScaled = true
    label.Size = UDim2.fromScale(1, 1)
    label.Parent = bb
    task.delay((evt.ticks or 5) * TICK_RATE, function()
        if bb then bb:Destroy() end
    end)
end

handlers.buff = function(_evt) end
handlers.gold = function(_evt) end

-- ---------- public API ---------- --

function CombatRenderer.Init(deps)
    -- MomentService is optional -- CombatRenderer still works without it
    -- (Phase 1-11 behavior). Init is called from ClientMain after
    -- MomentService itself is required.
    if deps and deps.MomentService then
        MomentService = deps.MomentService
    end
end

function CombatRenderer.PlayEvents(payload)
    if type(payload) ~= "table" then return end
    local events = payload.events
    if events == nil and payload[1] and payload[1].kind then
        events = payload
    end
    if not events or #events == 0 then return end

    -- Cancel any in-flight playback
    if currentPlayback then
        task.cancel(currentPlayback)
        currentPlayback = nil
    end

    -- Give replication up to 1s to settle before we demand the first actor.
    local deadline = os.clock() + 1.0
    while os.clock() < deadline do
        scanActors()
        if next(actorModels) then break end
        task.wait(0.05)
    end

    local byTick: {[number]: {any}} = {}
    local maxTick = 0
    for _, e in ipairs(events) do
        local t = e.tick or 0
        byTick[t] = byTick[t] or {}
        table.insert(byTick[t], e)
        if t > maxTick then maxTick = t end
    end

    currentPlayback = task.spawn(function()
        for t = 0, maxTick do
            local batch = byTick[t]
            if batch then
                for _, e in ipairs(batch) do
                    local h = handlers[e.kind]
                    if h then
                        local ok, err = pcall(h, e)
                        if not ok then
                            warn(("[CombatRenderer] handler '%s' error: %s"):format(e.kind, tostring(err)))
                        end
                    end
                end
            end
            task.wait(TICK_RATE)
        end
        currentPlayback = nil
    end)
end

return CombatRenderer
