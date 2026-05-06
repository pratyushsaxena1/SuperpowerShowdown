local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config  = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Ranks   = require(Shared:WaitForChild("Ranks"))

local EloService     = require(script.Parent:WaitForChild("EloService"))
local CombatService  = require(script.Parent:WaitForChild("CombatService"))
local PadService     = require(script.Parent:WaitForChild("PadService"))
local MatchService   = require(script.Parent:WaitForChild("MatchService"))
local EffectService  = require(script.Parent:WaitForChild("EffectService"))
local StatsService   = require(script.Parent:WaitForChild("StatsService"))

-- World construction ---------------------------------------------------------

local function makePart(name, size, position, color, parent, anchored)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Color = color
	p.Anchored = anchored ~= false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or workspace
	return p
end

local function makeNeonEdge(name, size, position, color, parent)
	local p = makePart(name, size, position, color, parent)
	p.Material = Enum.Material.Neon
	return p
end

local function makePillar(position, height, color, parent, capColor)
	local pillar = makePart("Pillar", Vector3.new(4, height, 4), position + Vector3.new(0, height/2, 0),
		color, parent)
	pillar.Material = Enum.Material.Marble
	local cap = makeNeonEdge("PillarCap", Vector3.new(5, 0.5, 5),
		position + Vector3.new(0, height + 0.25, 0), capColor or Color3.fromRGB(255, 230, 120), parent)
	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 18
	light.Color = capColor or Color3.fromRGB(255, 230, 120)
	light.Parent = cap
	return pillar
end

local function setupLighting()
	Lighting.Ambient = Color3.fromRGB(60, 60, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 130, 160)
	Lighting.Brightness = 2.4
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 30
	Lighting.FogStart = 200
	Lighting.FogEnd = 1500
	Lighting.FogColor = Color3.fromRGB(30, 36, 56)

	-- Sky
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	sky.SunAngularSize = 18
	sky.MoonAngularSize = 11
	sky.StarCount = 3000

	-- Atmosphere for depth
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.25
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(220, 220, 240)
	atmosphere.Decay = Color3.fromRGB(110, 80, 140)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1.5

	-- Sun rays
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if not rays then
		rays = Instance.new("SunRaysEffect")
		rays.Parent = Lighting
	end
	rays.Intensity = 0.18
	rays.Spread = 0.85

	-- Bloom for those neon highlights
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.0

	-- Subtle color grading
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Parent = Lighting
	end
	cc.Saturation = 0.15
	cc.Contrast = 0.05
end

local function buildLobby()
	-- Main platform
	local floor = makePart("LobbyFloor", Vector3.new(160, 2, 160), Vector3.new(0, 0, 0),
		Color3.fromRGB(36, 40, 60), workspace)
	floor.Material = Enum.Material.Slate

	-- Decorative neon edges
	for _, off in ipairs({-80, 80}) do
		makeNeonEdge("LobbyEdgeX", Vector3.new(160, 0.4, 1.4), Vector3.new(0, 0.95, off),
			Color3.fromRGB(120, 220, 255), workspace)
		makeNeonEdge("LobbyEdgeZ", Vector3.new(1.4, 0.4, 160), Vector3.new(off, 0.95, 0),
			Color3.fromRGB(120, 220, 255), workspace)
	end

	-- Center logo plate
	local plate = makeNeonEdge("LobbyPlate", Vector3.new(40, 0.2, 40), Vector3.new(0, 1.05, 0),
		Color3.fromRGB(255, 200, 120), workspace)
	plate.Transparency = 0.3

	-- Floating sign above the center
	local sign = makePart("LobbySign", Vector3.new(50, 8, 1), Vector3.new(0, 35, -40),
		Color3.fromRGB(20, 24, 38), workspace)
	sign.Material = Enum.Material.Neon
	sign.Transparency = 0.15
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(900, 220)
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = sign
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.6, 0)
	title.BackgroundTransparency = 1
	title.Text = "SUPERPOWER SHOWDOWN"
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(255, 230, 120)
	title.TextStrokeTransparency = 0
	title.Parent = bb
	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, 0, 0.4, 0)
	subtitle.Position = UDim2.new(0, 0, 0.6, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Ranked 1v1 Duels  •  10 Powers  •  Climb the Ladder"
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextColor3 = Color3.fromRGB(220, 220, 240)
	subtitle.TextStrokeTransparency = 0
	subtitle.Parent = bb

	-- Decorative pillars at the corners
	local pillarColors = {
		Color3.fromRGB(120, 200, 255),
		Color3.fromRGB(255, 130, 60),
		Color3.fromRGB(170, 100, 220),
		Color3.fromRGB(255, 230, 100),
	}
	local positions = {
		Vector3.new(-60, 1, -60), Vector3.new(60, 1, -60),
		Vector3.new(-60, 1, 60), Vector3.new(60, 1, 60),
	}
	for i, pos in ipairs(positions) do
		makePillar(pos, 18, Color3.fromRGB(40, 40, 60), workspace, pillarColors[i])
	end

	-- Lobby spawn
	local sp = workspace:FindFirstChild("LobbySpawn")
	if not sp then
		sp = Instance.new("SpawnLocation")
		sp.Name = "LobbySpawn"
		sp.Anchored = true
		sp.Size = Vector3.new(8, 1, 8)
		sp.Position = Config.LOBBY_SPAWN - Vector3.new(0, 4, 0)
		sp.Neutral = true
		sp.Color = Color3.fromRGB(60, 200, 120)
		sp.Material = Enum.Material.Neon
		sp.Parent = workspace
	end
end

local function buildArena()
	-- Floor
	local floor = makePart("ArenaFloor", Vector3.new(160, 2, 160),
		Vector3.new(0, 0, 500), Color3.fromRGB(28, 30, 44), workspace)
	floor.Material = Enum.Material.Slate

	-- Center ring
	local center = makeNeonEdge("ArenaCenter", Vector3.new(60, 0.2, 60),
		Vector3.new(0, 1.05, 500), Color3.fromRGB(120, 90, 220), workspace)
	center.Transparency = 0.55

	-- Walls + neon trim
	for i, off in ipairs({ -80, 80 }) do
		makePart("ArenaWallX" .. i, Vector3.new(2, 30, 160),
			Vector3.new(off, 15, 500), Color3.fromRGB(46, 50, 70), workspace)
		makeNeonEdge("ArenaWallXTop" .. i, Vector3.new(2.6, 0.6, 160),
			Vector3.new(off, 30.3, 500), Color3.fromRGB(120, 200, 255), workspace)
	end
	for i, off in ipairs({ -80, 80 }) do
		makePart("ArenaWallZ" .. i, Vector3.new(160, 30, 2),
			Vector3.new(0, 15, 500 + off), Color3.fromRGB(46, 50, 70), workspace)
		makeNeonEdge("ArenaWallZTop" .. i, Vector3.new(160, 0.6, 2.6),
			Vector3.new(0, 30.3, 500 + off), Color3.fromRGB(255, 130, 200), workspace)
	end

	-- Decorative pillars at corners (with team colors)
	local cornerPositions = {
		{ Vector3.new(-70, 1, 430), Color3.fromRGB(120, 200, 255) },
		{ Vector3.new( 70, 1, 430), Color3.fromRGB(255, 100, 130) },
		{ Vector3.new(-70, 1, 570), Color3.fromRGB(120, 200, 255) },
		{ Vector3.new( 70, 1, 570), Color3.fromRGB(255, 100, 130) },
	}
	for _, e in ipairs(cornerPositions) do
		makePillar(e[1], 22, Color3.fromRGB(40, 40, 60), workspace, e[2])
	end

	-- Player spawn markers (visual only, blue/red glowing rings)
	for i, e in ipairs({
		{ Config.ARENA_A_POS - Vector3.new(0, 4, 0), Color3.fromRGB(80, 180, 255) },
		{ Config.ARENA_B_POS - Vector3.new(0, 4, 0), Color3.fromRGB(255, 100, 130) },
	}) do
		local marker = makeNeonEdge("ArenaSpawnMarker" .. i, Vector3.new(8, 0.3, 8),
			e[1], e[2], workspace)
		marker.Transparency = 0.3
	end

	-- "ARENA" sign hovering
	local sign = makePart("ArenaSign", Vector3.new(40, 6, 1),
		Vector3.new(0, 38, 420), Color3.fromRGB(20, 24, 38), workspace)
	sign.Material = Enum.Material.Neon
	sign.Transparency = 0.25
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(720, 140)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = sign
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "⚔  ARENA  ⚔"
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextColor3 = Color3.fromRGB(255, 230, 120)
	lbl.TextStrokeTransparency = 0
	lbl.Parent = bb
end

setupLighting()
buildLobby()
buildArena()

-- Services -------------------------------------------------------------------

local elo     = EloService.new()
local stats   = StatsService.new()
local effects = EffectService.new()
local combat  = CombatService.new({ effects = effects })
local pad     = PadService.new(elo, function() end)
local match   = MatchService.new({
	elo = elo, combat = combat, pad = pad, effects = effects, stats = stats,
})

pad._onMatchReady = function(a, b) match:Start(a, b) end
pad:Build()
pad:Start()

-- Player lifecycle -----------------------------------------------------------

local function buildOverhead(player, char)
	local head = char:WaitForChild("Head", 5)
	if not head then return end
	local existing = head:FindFirstChild("EloBillboard")
	if existing then existing:Destroy() end

	local bb = Instance.new("BillboardGui")
	bb.Name = "EloBillboard"
	bb.Size = UDim2.fromOffset(220, 78)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = head

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = bb

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, 0, 0.42, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = player.Name
	nameLbl.TextColor3 = Color3.new(1, 1, 1)
	nameLbl.TextStrokeTransparency = 0
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.TextScaled = true
	nameLbl.Parent = frame

	local rankLbl = Instance.new("TextLabel")
	rankLbl.Name = "RankLabel"
	rankLbl.Size = UDim2.new(1, 0, 0.32, 0)
	rankLbl.Position = UDim2.new(0, 0, 0.42, 0)
	rankLbl.BackgroundTransparency = 1
	rankLbl.Text = "—"
	rankLbl.Font = Enum.Font.GothamBold
	rankLbl.TextScaled = true
	rankLbl.TextStrokeTransparency = 0
	rankLbl.Parent = frame

	local eloLbl = Instance.new("TextLabel")
	eloLbl.Name = "EloLabel"
	eloLbl.Size = UDim2.new(1, 0, 0.26, 0)
	eloLbl.Position = UDim2.new(0, 0, 0.74, 0)
	eloLbl.BackgroundTransparency = 1
	eloLbl.Text = "Elo: " .. tostring(elo:Get(player))
	eloLbl.TextColor3 = Color3.fromRGB(220, 220, 240)
	eloLbl.TextStrokeTransparency = 0
	eloLbl.Font = Enum.Font.Gotham
	eloLbl.TextScaled = true
	eloLbl.Parent = frame
end

local function refreshOverhead(player)
	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	local bb = head and head:FindFirstChild("EloBillboard")
	local frame = bb and bb:FindFirstChildOfClass("Frame")
	if not frame then return end
	local rankLbl = frame:FindFirstChild("RankLabel")
	local eloLbl  = frame:FindFirstChild("EloLabel")
	local e = elo:Get(player)
	local tier = Ranks.fromElo(e)
	if rankLbl then
		rankLbl.Text = string.upper(tier.name)
		rankLbl.TextColor3 = tier.accent
	end
	if eloLbl then
		eloLbl.Text = "Elo: " .. tostring(e)
	end
end

local function attachOverhead(player)
	local function bind(char) buildOverhead(player, char); task.wait(0.1); refreshOverhead(player) end
	if player.Character then bind(player.Character) end
	player.CharacterAdded:Connect(bind)
end

Players.PlayerAdded:Connect(function(player)
	elo:Load(player)
	stats:Load(player)
	attachOverhead(player)
	-- Push the initial stats payload to client.
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		stats:Push(player)
	end)
end)

for _, p in ipairs(Players:GetPlayers()) do
	elo:Load(p)
	stats:Load(p)
	attachOverhead(p)
	stats:Push(p)
end

Players.PlayerRemoving:Connect(function(player)
	match:HandlePlayerLeaving(player)
	pad:SetBusy(player, false)
	elo:Save(player)
	stats:Save(player)
end)

-- Refresh over-head Elo/rank when it changes.
local lastShownElo = setmetatable({}, { __mode = "k" })
RunService.Heartbeat:Connect(function()
	for _, p in ipairs(Players:GetPlayers()) do
		local cur = elo:Get(p)
		if cur ~= lastShownElo[p] then
			lastShownElo[p] = cur
			refreshOverhead(p)
		end
	end
end)

Remotes.GetMyElo.OnServerInvoke = function(player)
	return elo:Get(player), Ranks.fromElo(elo:Get(player))
end

Remotes.GetMyStats.OnServerInvoke = function(player)
	return stats:Get(player)
end

Remotes.GetTopPlayers.OnServerInvoke = function(_player)
	local list = elo:GetTop(10)
	-- Decorate with rank tier names.
	for _, e in ipairs(list) do
		e.rank = Ranks.label(e.elo)
	end
	return list
end

print("[SuperpowerShowdown] Server ready.")
