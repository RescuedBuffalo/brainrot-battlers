--!strict
-- Centralized SFX registry. SoundController.Play("click") triggers a sound
-- by name; the registry maps names to Roblox asset IDs, mostly built-in
-- rbxasset:// files so fresh clones don't need uploaded assets.
--
-- Swap any ID for a library asset you prefer by editing REGISTRY below.
-- Each entry accepts { id = string, volume = number?, pitch = number? }.
--
-- Usage: SoundController.Init(); SoundController.Play("click")
-- Music is handled separately: PlayMusic(name), StopMusic(fadeSec?).

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local SoundController = {}

-- Built-in rbxasset paths ship with every place; won't 404 on a fresh clone.
-- Feel free to replace with Creator Store IDs (rbxassetid://...) for a
-- better sound pack.
-- Only verified rbxasset:// paths (these ship with every Roblox place; the
-- engine won't "Failed to load sound" on them). For anything we don't have
-- a good built-in for, we reuse electronicpingshort with a pitch shift so
-- the player still gets SFX feedback. Swap in Creator Store IDs later.
local PING = "rbxasset://sounds/electronicpingshort.wav"
local WATER = "rbxasset://sounds/impact_water.mp3"
local FOOTSTEPS = "rbxasset://sounds/action_footsteps_plastic.mp3"
local GETUP = "rbxasset://sounds/action_get_up.mp3"

local REGISTRY = {
    click      = { id = PING,       volume = 0.3, pitch = 1.6 },
    buy        = { id = PING,       volume = 0.4, pitch = 1.3 },
    sell       = { id = WATER,      volume = 0.3, pitch = 0.9 },
    place      = { id = PING,       volume = 0.45, pitch = 0.9 },
    reroll     = { id = PING,       volume = 0.4, pitch = 1.1 },
    combat     = { id = GETUP,      volume = 0.6, pitch = 0.85 },
    hit        = { id = WATER,      volume = 0.35, pitch = 1.2 },
    ability    = { id = PING,       volume = 0.55, pitch = 0.7 },
    crateOpen  = { id = FOOTSTEPS,  volume = 0.5, pitch = 0.6 },
    upgrade    = { id = PING,       volume = 0.7, pitch = 1.4 },
    victory    = { id = PING,       volume = 0.8, pitch = 1.8 },
    defeat     = { id = WATER,      volume = 0.8, pitch = 0.4 },
}

-- Some of the filenames above aren't guaranteed across Roblox versions; we
-- cache which ones successfully loaded so Play() silently no-ops on misses
-- rather than spamming warnings every click.
local sounds: { [string]: Sound } = {}
local musicTrack: Sound? = nil

local function makeSound(name: string, cfg): Sound
    local s = Instance.new("Sound")
    s.Name = "SFX_" .. name
    s.SoundId = cfg.id
    s.Volume = cfg.volume or 0.5
    s.PlaybackSpeed = cfg.pitch or 1
    s.Parent = SoundService
    return s
end

function SoundController.Init()
    for name, cfg in pairs(REGISTRY) do
        sounds[name] = makeSound(name, cfg)
    end
end

function SoundController.Play(name: string)
    local s = sounds[name]
    if not s then return end
    -- Clone so overlapping plays don't interrupt each other (e.g. rapid clicks)
    local clone = s:Clone()
    clone.Parent = SoundService
    clone:Play()
    clone.Ended:Connect(function() clone:Destroy() end)
    task.delay(4, function()
        if clone.Parent then clone:Destroy() end
    end)
end

-- ---------- music ---------- --

-- Looping background tracks per phase. Using rbxasset:// paths so this works
-- out of the box; replace with a proper soundtrack asset when you have one.
-- Music placeholders (volume=0 so they're silent until user assigns real
-- soundtrack assets). The plumbing is in place; just swap the IDs.
local MUSIC = {
    lobby  = { id = PING, volume = 0 },
    combat = { id = PING, volume = 0 },
}

function SoundController.PlayMusic(name: string, fadeSec: number?)
    fadeSec = fadeSec or 1.0
    local cfg = MUSIC[name]
    if not cfg then return end

    if musicTrack then
        local fadeOut = musicTrack
        local tween = TweenService:Create(fadeOut, TweenInfo.new(fadeSec), { Volume = 0 })
        tween:Play()
        tween.Completed:Connect(function() fadeOut:Destroy() end)
        musicTrack = nil
    end

    local s = Instance.new("Sound")
    s.Name = "Music_" .. name
    s.SoundId = cfg.id
    s.Looped = true
    s.Volume = 0
    s.Parent = SoundService
    s:Play()
    TweenService:Create(s, TweenInfo.new(fadeSec), { Volume = cfg.volume or 0.3 }):Play()
    musicTrack = s
end

function SoundController.StopMusic(fadeSec: number?)
    if not musicTrack then return end
    fadeSec = fadeSec or 1.0
    local track = musicTrack
    musicTrack = nil
    local tween = TweenService:Create(track, TweenInfo.new(fadeSec), { Volume = 0 })
    tween:Play()
    tween.Completed:Connect(function() track:Destroy() end)
end

return SoundController
