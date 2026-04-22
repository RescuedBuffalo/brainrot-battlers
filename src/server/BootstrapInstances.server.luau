--!strict
-- Recreates all non-code Instances that live alongside this project in the
-- Studio place: RemoteEvents/RemoteFunctions, UnitTemplates models, the
-- BattleArena tile grid, and LobbyHub placeholder. Runs once on server boot,
-- idempotent: skips anything that already exists.
--
-- This lets a fresh clone of the repo (Rojo sync into an empty place) come up
-- with a fully functional world without any manual Studio setup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- ---------- folders + remotes ---------- --

local function ensureFolder(parent: Instance, name: string): Folder
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("Folder") then return existing end
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

local remotes = ensureFolder(ReplicatedStorage, "Remotes")
ensureFolder(ReplicatedStorage, "UnitTemplates")

local REMOTE_EVENTS = {
    "BuyUnit", "SellUnit", "PlaceUnit", "RerollShop",
    "BuyXP", "StartCombat", "NextRound", "OpenCrate",
    "StateUpdate", "CombatEvent", "CrateReveal",
    -- Phase 12 additions
    "SelectNextNode",   -- client -> server, { nodeId }
    "CardChoice",       -- client -> server, { cardId, targetUnitInstanceId? }
}
for _, name in ipairs(REMOTE_EVENTS) do
    if not remotes:FindFirstChild(name) then
        local r = Instance.new("RemoteEvent")
        r.Name = name
        r.Parent = remotes
    end
end
if not remotes:FindFirstChild("GetPlayerState") then
    local rf = Instance.new("RemoteFunction")
    rf.Name = "GetPlayerState"
    rf.Parent = remotes
end

-- ---------- world: lobby + arena ---------- --

local lobby = Workspace:FindFirstChild("LobbyHub")
if not lobby then
    lobby = Instance.new("Model")
    lobby.Name = "LobbyHub"
    lobby.Parent = Workspace
end

-- Lobby geometry: elevated platform with 10 pedestals arranged in an arc
-- facing a glowing portal. SpawnLocation sits at the arc's center so the
-- player joins inside the lobby and can walk through the portal.
-- Offset from the arena (which lives at origin) by 80 studs along -X.
local LOBBY_CENTER_X = -80
local LOBBY_CENTER_Z = 0
local LOBBY_Y = 40  -- platform top
local PEDESTAL_COUNT = 10
local PEDESTAL_ARC_RADIUS = 24
local PEDESTAL_ARC_DEG = 160

if #lobby:GetChildren() < 4 then
    -- Wipe any stale children so the rebuild is deterministic
    for _, c in ipairs(lobby:GetChildren()) do c:Destroy() end

    local platform = Instance.new("Part")
    platform.Name = "Platform"
    platform.Anchored = true
    platform.Size = Vector3.new(64, 1, 64)
    platform.Position = Vector3.new(LOBBY_CENTER_X, LOBBY_Y, LOBBY_CENTER_Z)
    platform.Material = Enum.Material.Marble
    platform.Color = Color3.fromRGB(55, 45, 90)
    platform.TopSurface = Enum.SurfaceType.Smooth
    platform.BottomSurface = Enum.SurfaceType.Smooth
    platform.Parent = lobby

    -- Decorative rim
    local rim = Instance.new("Part")
    rim.Name = "Rim"
    rim.Anchored = true
    rim.CanCollide = false
    rim.Size = Vector3.new(66, 0.4, 66)
    rim.Position = Vector3.new(LOBBY_CENTER_X, LOBBY_Y + 0.5, LOBBY_CENTER_Z)
    rim.Material = Enum.Material.Neon
    rim.Color = Color3.fromRGB(180, 100, 220)
    rim.Transparency = 0.4
    rim.TopSurface = Enum.SurfaceType.Smooth
    rim.Parent = lobby

    local pedestals = ensureFolder(lobby, "Pedestals")
    local platformTop = LOBBY_Y + 0.5

    local UNIT_IDS = {
        "skibidi", "sigma", "gyatt", "tralalero", "bombardiro",
        "tungtung", "ballerina", "capuchino", "fanum", "ohio",
    }
    -- Arc centered on -Z (facing the portal). Sweep ARC_DEG degrees from
    -- left to right so the pedestals form a semicircle opening toward the
    -- portal.
    local halfSweep = math.rad(PEDESTAL_ARC_DEG / 2)
    for i, unitId in ipairs(UNIT_IDS) do
        local t = (i - 1) / (PEDESTAL_COUNT - 1)
        local theta = -halfSweep + t * (2 * halfSweep)
        -- Offset the arc center so it opens toward +Z (portal is at +Z)
        local x = LOBBY_CENTER_X + math.sin(theta) * PEDESTAL_ARC_RADIUS
        local z = LOBBY_CENTER_Z - math.cos(theta) * PEDESTAL_ARC_RADIUS

        local pedestal = Instance.new("Part")
        pedestal.Name = "Pedestal_" .. unitId
        pedestal.Anchored = true
        pedestal.CanCollide = true
        pedestal.Shape = Enum.PartType.Cylinder
        -- Cylinder primitive has its length on the X axis; rotate to stand up.
        pedestal.Size = Vector3.new(4, 3.6, 3.6)
        pedestal.CFrame = CFrame.new(x, platformTop + 1.8, z) * CFrame.Angles(0, 0, math.rad(90))
        pedestal.Material = Enum.Material.Marble
        pedestal.Color = Color3.fromRGB(70, 55, 100)
        pedestal.TopSurface = Enum.SurfaceType.Smooth
        pedestal.BottomSurface = Enum.SurfaceType.Smooth
        pedestal:SetAttribute("UnitId", unitId)
        pedestal.Parent = pedestals
    end

    -- Portal: a tall, glowing pink slab with a PointLight. Kids love flex.
    local portal = Instance.new("Part")
    portal.Name = "Portal"
    portal.Anchored = true
    portal.CanCollide = false
    portal.Size = Vector3.new(10, 14, 1.5)
    portal.Position = Vector3.new(LOBBY_CENTER_X, LOBBY_Y + 7.5, LOBBY_CENTER_Z + 16)
    portal.Material = Enum.Material.Neon
    portal.Color = Color3.fromRGB(255, 90, 200)
    portal.Transparency = 0.2
    portal.TopSurface = Enum.SurfaceType.Smooth
    portal.BottomSurface = Enum.SurfaceType.Smooth
    portal.Parent = lobby
    local portalLight = Instance.new("PointLight")
    portalLight.Color = portal.Color
    portalLight.Range = 40
    portalLight.Brightness = 3
    portalLight.Parent = portal

    local portalLabel = Instance.new("BillboardGui")
    portalLabel.Size = UDim2.fromOffset(240, 60)
    portalLabel.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
    portalLabel.AlwaysOnTop = true
    portalLabel.Parent = portal
    local portalText = Instance.new("TextLabel")
    portalText.Size = UDim2.fromScale(1, 1)
    portalText.BackgroundTransparency = 1
    portalText.Text = "⚔️ PLAY"
    portalText.TextColor3 = Color3.fromRGB(255, 220, 255)
    portalText.Font = Enum.Font.GothamBlack
    portalText.TextScaled = true
    portalText.TextStrokeColor3 = Color3.new(0, 0, 0)
    portalText.TextStrokeTransparency = 0
    portalText.Parent = portalLabel

    -- SpawnLocation near the arc center, facing the portal
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "LobbySpawn"
    spawn.Anchored = true
    spawn.CanCollide = true
    spawn.Size = Vector3.new(8, 1, 8)
    spawn.Position = Vector3.new(LOBBY_CENTER_X, LOBBY_Y + 1, LOBBY_CENTER_Z - 2)
    spawn.Color = Color3.fromRGB(255, 150, 230)
    spawn.Material = Enum.Material.Neon
    spawn.Transparency = 0.2
    spawn.TopSurface = Enum.SurfaceType.Smooth
    spawn.BottomSurface = Enum.SurfaceType.Smooth
    spawn.Neutral = true
    spawn.AllowTeamChangeOnTouch = false
    spawn.Parent = lobby
end

local arena = Workspace:FindFirstChild("BattleArena")
if not arena then
    arena = Instance.new("Model")
    arena.Name = "BattleArena"
    arena.Parent = Workspace
end
local tilesFolder = ensureFolder(arena, "Tiles")
ensureFolder(arena, "PlayerSide")
ensureFolder(arena, "EnemySide")

-- 6x6 tile grid -- skip if already populated
if #tilesFolder:GetChildren() < 36 then
    for _, c in ipairs(tilesFolder:GetChildren()) do c:Destroy() end

    local TILE_W, TILE_D, TILE_H = 4, 4, 0.4
    local COLS, ROWS = 6, 6
    local ORIGIN_X = -(COLS * TILE_W) / 2 + TILE_W / 2
    local ORIGIN_Z = -(ROWS * TILE_D) / 2 + TILE_D / 2

    local PLAYER_COLOR = Color3.fromRGB(70, 110, 180)
    local ENEMY_COLOR = Color3.fromRGB(180, 70, 80)
    local PLAYER_ROWS = { [3]=true, [4]=true, [5]=true }

    for x = 0, COLS - 1 do
        for y = 0, ROWS - 1 do
            local t = Instance.new("Part")
            t.Name = ("Tile_%d_%d"):format(x, y)
            t.Anchored = true
            t.CanCollide = false
            t.CanQuery = true
            t.CanTouch = false
            t.Size = Vector3.new(TILE_W - 0.1, TILE_H, TILE_D - 0.1)
            t.TopSurface = Enum.SurfaceType.Smooth
            t.BottomSurface = Enum.SurfaceType.Smooth
            t.Material = Enum.Material.SmoothPlastic
            t.Color = PLAYER_ROWS[y] and PLAYER_COLOR or ENEMY_COLOR
            t.Position = Vector3.new(ORIGIN_X + x * TILE_W, TILE_H / 2, ORIGIN_Z + y * TILE_D)
            t:SetAttribute("TileX", x)
            t:SetAttribute("TileY", y)
            t:SetAttribute("Side", PLAYER_ROWS[y] and "player" or "enemy")
            t.Parent = tilesFolder
        end
    end

    if not arena:FindFirstChild("ArenaBase") then
        local frame = Instance.new("Part")
        frame.Name = "ArenaBase"
        frame.Anchored = true
        frame.CanCollide = false
        frame.Size = Vector3.new(COLS * TILE_W + 2, 0.6, ROWS * TILE_D + 2)
        frame.Position = Vector3.new(0, -0.3, 0)
        frame.Color = Color3.fromRGB(30, 30, 40)
        frame.Material = Enum.Material.SmoothPlastic
        frame.TopSurface = Enum.SurfaceType.Smooth
        frame.BottomSurface = Enum.SurfaceType.Smooth
        frame.Parent = arena
    end
end

-- ---------- unit templates ---------- --
-- Only build if missing. Each template: Model with HumanoidRootPart (PrimaryPart,
-- invisible), Head (required by Humanoid + BillboardGui anchor), decorative body
-- parts, Humanoid (AutoRotate/BreakJointsOnDeath off because combat animates
-- via Model:PivotTo).

local templates = ReplicatedStorage:WaitForChild("UnitTemplates")
local TEMPLATE_NAMES = {
    "skibidi","sigma","gyatt","tralalero","bombardiro",
    "tungtung","ballerina","capuchino","fanum","ohio",
}
local needsTemplates = false
for _, name in ipairs(TEMPLATE_NAMES) do
    if not templates:FindFirstChild(name) then
        needsTemplates = true
        break
    end
end

if needsTemplates then
    for _, c in ipairs(templates:GetChildren()) do c:Destroy() end

    local function part(props: {any})
        local p = Instance.new("Part")
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        p.Material = Enum.Material.SmoothPlastic
        for k, v in pairs(props) do p[k] = v end
        return p
    end

    local function createTemplate(unitId: string, displayName: string, build: (Model, BasePart) -> ())
        local model = Instance.new("Model")
        model.Name = unitId

        local hrp = part({
            Name = "HumanoidRootPart",
            Size = Vector3.new(1.5, 1, 1),
            Transparency = 1,
            CFrame = CFrame.new(0, 0.5, 0),
        })
        hrp.Parent = model
        model.PrimaryPart = hrp

        build(model, hrp)

        local head = model:FindFirstChild("Head")
        assert(head, ("%s builder must create a Part named 'Head'"):format(unitId))

        local humanoid = Instance.new("Humanoid")
        humanoid.RequiresNeck = false
        humanoid.AutoRotate = false
        humanoid.BreakJointsOnDeath = false
        humanoid.Parent = model

        local bbAnchor = Instance.new("Attachment")
        bbAnchor.Name = "BillboardAnchor"
        bbAnchor.Position = Vector3.new(0, (head :: BasePart).Size.Y * 0.5 + 0.5, 0)
        bbAnchor.Parent = head

        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored = true
                p.CanCollide = false
                p.CanQuery = false
                p.CanTouch = false
            end
        end

        model:SetAttribute("DisplayName", displayName)
        model:SetAttribute("UnitId", unitId)
        model.Parent = templates
    end

    local C = {
        white=Color3.fromRGB(240,240,240), porc=Color3.fromRGB(220,225,230),
        stone=Color3.fromRGB(105,100,95), darkStone=Color3.fromRGB(60,55,50),
        fire=Color3.fromRGB(230,90,30), emb=Color3.fromRGB(255,170,50),
        sharkTop=Color3.fromRGB(90,120,150), sharkBot=Color3.fromRGB(220,225,230),
        denim=Color3.fromRGB(55,85,140), metal=Color3.fromRGB(160,160,170),
        croc=Color3.fromRGB(80,140,80), wood=Color3.fromRGB(120,85,50),
        bark=Color3.fromRGB(80,55,30), cream=Color3.fromRGB(240,225,190),
        coffee=Color3.fromRGB(110,70,40), pink=Color3.fromRGB(255,160,200),
        black=Color3.fromRGB(25,25,30), silver=Color3.fromRGB(200,205,215),
        gold=Color3.fromRGB(230,190,60), green=Color3.fromRGB(70,160,80),
        purple=Color3.fromRGB(120,40,160), red=Color3.fromRGB(180,30,40),
        skin=Color3.fromRGB(225,185,155),
    }

    createTemplate("skibidi", "Skibidi Scout", function(model)
        part({ Name="Bowl", Size=Vector3.new(2.4,1.6,2.4), Color=C.porc, Shape=Enum.PartType.Cylinder, CFrame=CFrame.new(0,0.8,0) * CFrame.Angles(0,0,math.rad(90)) }).Parent = model
        part({ Name="Seat", Size=Vector3.new(2.6,0.3,2.6), Color=C.white, CFrame=CFrame.new(0,1.75,0) }).Parent = model
        part({ Name="Tank", Size=Vector3.new(2.4,1.6,0.8), Color=C.porc, CFrame=CFrame.new(0,2.7,-0.9) }).Parent = model
        part({ Name="Head", Size=Vector3.new(1.6,1.6,1.4), Color=C.skin, Shape=Enum.PartType.Ball, CFrame=CFrame.new(0,2.9,0.2) }).Parent = model
        part({ Name="Eye1", Size=Vector3.new(0.25,0.25,0.25), Color=C.black, Shape=Enum.PartType.Ball, CFrame=CFrame.new(-0.3,3.05,0.85) }).Parent = model
        part({ Name="Eye2", Size=Vector3.new(0.25,0.25,0.25), Color=C.black, Shape=Enum.PartType.Ball, CFrame=CFrame.new(0.3,3.05,0.85) }).Parent = model
    end)

    createTemplate("sigma", "Sigma Slapper", function(model)
        part({ Name="Base", Size=Vector3.new(2.2,0.8,2.2), Color=C.darkStone, CFrame=CFrame.new(0,0.4,0) }).Parent = model
        part({ Name="Body", Size=Vector3.new(2.4,2.0,2.2), Color=C.stone, CFrame=CFrame.new(0,1.8,0) }).Parent = model
        part({ Name="Head", Size=Vector3.new(2.6,2.4,2.4), Color=C.stone, CFrame=CFrame.new(0,4.0,0) }).Parent = model
        part({ Name="Nose", Size=Vector3.new(0.5,1.2,0.6), Color=C.darkStone, CFrame=CFrame.new(0,4.0,1.35) }).Parent = model
        part({ Name="Brow", Size=Vector3.new(2.4,0.4,0.3), Color=C.darkStone, CFrame=CFrame.new(0,4.6,1.2) }).Parent = model
    end)

    createTemplate("gyatt", "Gyatt Gunner", function(model)
        part({ Name="Torso", Size=Vector3.new(1.6,2.0,1.0), Color=C.fire, CFrame=CFrame.new(0,1.5,0) }).Parent = model
        part({ Name="Head", Size=Vector3.new(1.2,1.2,1.2), Color=C.emb, Shape=Enum.PartType.Ball, CFrame=CFrame.new(0,3.1,0) }).Parent = model
        part({ Name="Flame", Size=Vector3.new(0.8,1.4,0.8), Color=C.fire, Shape=Enum.PartType.Cylinder, CFrame=CFrame.new(0,4.2,0) }).Parent = model
        part({ Name="LegL", Size=Vector3.new(0.6,1.0,0.8), Color=C.darkStone, CFrame=CFrame.new(-0.4,0.5,0) }).Parent = model
        part({ Name="LegR", Size=Vector3.new(0.6,1.0,0.8), Color=C.darkStone, CFrame=CFrame.new(0.4,0.5,0) }).Parent = model
        part({ Name="Gun", Size=Vector3.new(0.4,0.4,2.0), Color=C.metal, CFrame=CFrame.new(1.1,1.8,0.6) }).Parent = model
    end)

    createTemplate("tralalero", "Tralalero Tripler", function(model)
        part({ Name="JeansL", Size=Vector3.new(0.7,1.6,1.0), Color=C.denim, CFrame=CFrame.new(-0.45,0.8,0) }).Parent = model
        part({ Name="JeansR", Size=Vector3.new(0.7,1.6,1.0), Color=C.denim, CFrame=CFrame.new(0.45,0.8,0) }).Parent = model
        part({ Name="Belly", Size=Vector3.new(1.8,1.2,1.2), Color=C.sharkBot, CFrame=CFrame.new(0,2.0,0) }).Parent = model
        part({ Name="Head", Size=Vector3.new(1.8,1.4,2.4), Color=C.sharkTop, CFrame=CFrame.new(0,3.2,0.2) }).Parent = model
        part({ Name="Fin", Size=Vector3.new(0.3,1.0,0.8), Color=C.sharkTop, CFrame=CFrame.new(0,4.1,0) }).Parent = model
        part({ Name="Teeth", Size=Vector3.new(1.4,0.2,0.1), Color=C.white, CFrame=CFrame.new(0,3.0,1.45) }).Parent = model
    end)

    createTemplate("bombardiro", "Bombardiro Bomber", function(model)
        part({ Name="Fuselage", Size=Vector3.new(1.4,1.4,3.2), Color=C.metal, CFrame=CFrame.new(0,1.2,0) }).Parent = model
        part({ Name="WingL", Size=Vector3.new(2.6,0.2,1.2), Color=C.metal, CFrame=CFrame.new(-1.8,1.2,0) }).Parent = model
        part({ Name="WingR", Size=Vector3.new(2.6,0.2,1.2), Color=C.metal, CFrame=CFrame.new(1.8,1.2,0) }).Parent = model
        part({ Name="Tail", Size=Vector3.new(0.3,1.0,0.8), Color=C.metal, CFrame=CFrame.new(0,2.0,-1.4) }).Parent = model
        part({ Name="Head", Size=Vector3.new(1.2,1.0,2.2), Color=C.croc, CFrame=CFrame.new(0,1.3,2.2) }).Parent = model
        part({ Name="Jaw", Size=Vector3.new(1.1,0.2,2.0), Color=C.croc, CFrame=CFrame.new(0,0.85,2.2) }).Parent = model
        part({ Name="Bomb", Size=Vector3.new(0.8,0.8,1.6), Color=C.black, Shape=Enum.PartType.Cylinder, CFrame=CFrame.new(0,0.4,0) * CFrame.Angles(0,math.rad(90),math.rad(90)) }).Parent = model
    end)

    createTemplate("tungtung", "Tung Tung Tanker", function(model)
        part({ Name="Body", Size=Vector3.new(2.2,3.6,2.2), Color=C.wood, Shape=Enum.PartType.Cylinder, CFrame=CFrame.new(0,1.8,0) * CFrame.Angles(0,0,math.rad(90)) }).Parent = model
        part({ Name="Ring1", Size=Vector3.new(2.35,0.2,2.35), Color=C.bark, CFrame=CFrame.new(0,0.8,0) }).Parent = model
        part({ Name="Ring2", Size=Vector3.new(2.35,0.2,2.35), Color=C.bark, CFrame=CFrame.new(0,2.4,0) }).Parent = model
        part({ Name="Head", Size=Vector3.new(1.8,1.6,1.8), Color=C.bark, Shape=Enum.PartType.Cylinder, CFrame=CFrame.new(0,4.4,0) * CFrame.Angles(0,0,math.rad(90)) }).Parent = model
        part({ Name="ArmL", Size=Vector3.new(0.5,0.5,1.6), Color=C.wood, CFrame=CFrame.new(-1.8,2.0,0) }).Parent = model
        part({ Name="ArmR", Size=Vector3.new(0.5,0.5,1.6), Color=C.wood, CFrame=CFrame.new(1.8,2.0,0) }).Parent = model
    end)

    createTemplate("ballerina", "Ballerina Cappuccina", function(model)
        part({ Name="Cup", Size=Vector3.new(1.8,2.0,1.8), Color=C.cream, Shape=Enum.PartType.Cylinder, CFrame=CFrame.new(0,1.0,0) * CFrame.Angles(0,0,math.rad(90)) }).Parent = model
        part({ Name="Tutu", Size=Vector3.new(2.8,0.4,2.8), Color=C.pink, CFrame=CFrame.new(0,2.0,0) }).Parent = model
        part({ Name="Torso", Size=Vector3.new(1.0,1.2,0.8), Color=C.cream, CFrame=CFrame.new(0,2.8,0) }).Parent = model
        part({ Name="Head", Size=Vector3.new(1.2,1.2,1.2), Color=C.coffee, Shape=Enum.PartType.Ball, CFrame=CFrame.new(0,4.0,0) }).Parent = model
        part({ Name="Foam", Size=Vector3.new(1.0,0.3,1.0), Color=C.white, CFrame=CFrame.new(0,4.7,0) }).Parent = model
        part({ Name="Handle", Size=Vector3.new(0.3,1.0,0.3), Color=C.cream, CFrame=CFrame.new(1.1,1.0,0) }).Parent = model
    end)

    createTemplate("capuchino", "Capuchino Assasino", function(model)
        part({ Name="Cloak", Size=Vector3.new(1.8,2.4,1.0), Color=C.black, CFrame=CFrame.new(0,1.3,0) }).Parent = model
        part({ Name="Head", Size=Vector3.new(1.0,1.0,1.0), Color=C.coffee, CFrame=CFrame.new(0,3.1,0) }).Parent = model
        part({ Name="Hood", Size=Vector3.new(1.3,0.6,1.3), Color=C.black, CFrame=CFrame.new(0,3.7,0) }).Parent = model
        part({ Name="DaggerL", Size=Vector3.new(0.15,1.2,0.05), Color=C.silver, CFrame=CFrame.new(-1.1,1.3,0) }).Parent = model
        part({ Name="DaggerR", Size=Vector3.new(0.15,1.2,0.05), Color=C.silver, CFrame=CFrame.new(1.1,1.3,0) }).Parent = model
        part({ Name="Legs", Size=Vector3.new(1.4,0.4,1.0), Color=C.black, CFrame=CFrame.new(0,0.2,0) }).Parent = model
    end)

    createTemplate("fanum", "Fanum Tax Collector", function(model)
        part({ Name="Torso", Size=Vector3.new(1.8,2.0,1.2), Color=C.green, CFrame=CFrame.new(0,1.3,0) }).Parent = model
        part({ Name="Head", Size=Vector3.new(1.3,1.3,1.3), Color=C.skin, Shape=Enum.PartType.Ball, CFrame=CFrame.new(0,3.0,0) }).Parent = model
        part({ Name="Hat", Size=Vector3.new(1.6,0.5,1.6), Color=C.gold, Shape=Enum.PartType.Cylinder, CFrame=CFrame.new(0,3.9,0) * CFrame.Angles(0,0,math.rad(90)) }).Parent = model
        part({ Name="Bag", Size=Vector3.new(1.2,1.4,1.0), Color=C.wood, CFrame=CFrame.new(1.4,0.7,0) }).Parent = model
        part({ Name="Dollar", Size=Vector3.new(0.8,0.8,0.1), Color=C.gold, CFrame=CFrame.new(0,1.6,0.7) }).Parent = model
        part({ Name="Legs", Size=Vector3.new(1.4,0.4,1.2), Color=C.darkStone, CFrame=CFrame.new(0,0.2,0) }).Parent = model
    end)

    createTemplate("ohio", "Ohio Final Boss", function(model)
        part({ Name="Base", Size=Vector3.new(2.8,0.6,2.8), Color=C.red, CFrame=CFrame.new(0,0.3,0) }).Parent = model
        part({ Name="Body", Size=Vector3.new(2.2,2.6,2.2), Color=C.purple, CFrame=CFrame.new(0,1.9,0) }).Parent = model
        part({ Name="Head", Size=Vector3.new(2.2,1.8,2.0), Color=C.red, CFrame=CFrame.new(0,4.0,0) }).Parent = model
        part({ Name="HornL", Size=Vector3.new(0.4,1.4,0.4), Color=C.black, Shape=Enum.PartType.Cylinder, CFrame=CFrame.new(-0.7,5.4,0) }).Parent = model
        part({ Name="HornR", Size=Vector3.new(0.4,1.4,0.4), Color=C.black, Shape=Enum.PartType.Cylinder, CFrame=CFrame.new(0.7,5.4,0) }).Parent = model
        part({ Name="EyeL", Size=Vector3.new(0.4,0.4,0.2), Color=C.gold, Shape=Enum.PartType.Ball, CFrame=CFrame.new(-0.5,4.2,1.0) }).Parent = model
        part({ Name="EyeR", Size=Vector3.new(0.4,0.4,0.2), Color=C.gold, Shape=Enum.PartType.Ball, CFrame=CFrame.new(0.5,4.2,1.0) }).Parent = model
    end)
end

print("[Bootstrap] instances ready")
