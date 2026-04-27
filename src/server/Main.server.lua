local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local EloService    = require(script.Parent:WaitForChild("EloService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local PadService    = require(script.Parent:WaitForChild("PadService"))
local MatchService  = require(script.Parent:WaitForChild("MatchService"))

-- World geometry --------------------------------------------------------------

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

local function buildLobby()
	makePart("LobbyFloor", Vector3.new(120, 1, 120), Vector3.new(0, 0, 0),
		Color3.fromRGB(70, 90, 130), workspace)
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
	makePart("ArenaFloor", Vector3.new(120, 1, 120), Vector3.new(0, 0, 500),
		Color3.fromRGB(50, 50, 60), workspace)
	for i, off in ipairs({ -60, 60 }) do
		makePart("ArenaWallX" .. i, Vector3.new(2, 30, 120),
			Vector3.new(off, 15, 500), Color3.fromRGB(80, 80, 100), workspace)
	end
	for i, off in ipairs({ -60, 60 }) do
		makePart("ArenaWallZ" .. i, Vector3.new(120, 30, 2),
			Vector3.new(0, 15, 500 + off), Color3.fromRGB(80, 80, 100), workspace)
	end
end

buildLobby()
buildArena()

-- Services --------------------------------------------------------------------

local elo    = EloService.new()
local combat = CombatService.new()
local pad    = PadService.new(elo, function() end) -- onMatchReady set below
local match  = MatchService.new({ elo = elo, combat = combat, pad = pad })

pad._onMatchReady = function(a, b) match:Start(a, b) end
pad:Build()
pad:Start()

-- Player lifecycle ------------------------------------------------------------

local function attachEloBillboard(player)
	local function bind(char)
		local head = char:WaitForChild("Head", 5)
		if not head then return end
		local existing = head:FindFirstChild("EloBillboard")
		if existing then existing:Destroy() end
		local bb = Instance.new("BillboardGui")
		bb.Name = "EloBillboard"
		bb.Size = UDim2.fromOffset(180, 50)
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.AlwaysOnTop = true
		bb.Parent = head
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = bb
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, 0, 0.55, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = player.Name
		nameLbl.TextColor3 = Color3.new(1, 1, 1)
		nameLbl.TextStrokeTransparency = 0
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextScaled = true
		nameLbl.Parent = frame
		local eloLbl = Instance.new("TextLabel")
		eloLbl.Name = "EloLabel"
		eloLbl.Size = UDim2.new(1, 0, 0.45, 0)
		eloLbl.Position = UDim2.new(0, 0, 0.55, 0)
		eloLbl.BackgroundTransparency = 1
		eloLbl.Text = "Elo: " .. tostring(elo:Get(player))
		eloLbl.TextColor3 = Color3.fromRGB(255, 220, 120)
		eloLbl.TextStrokeTransparency = 0
		eloLbl.Font = Enum.Font.GothamBold
		eloLbl.TextScaled = true
		eloLbl.Parent = frame
	end
	if player.Character then bind(player.Character) end
	player.CharacterAdded:Connect(bind)
end

local function refreshEloLabel(player)
	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	local bb = head and head:FindFirstChild("EloBillboard")
	local frame = bb and bb:FindFirstChildOfClass("Frame")
	local lbl = frame and frame:FindFirstChild("EloLabel")
	if lbl then lbl.Text = "Elo: " .. tostring(elo:Get(player)) end
end

Players.PlayerAdded:Connect(function(player)
	elo:Load(player)
	attachEloBillboard(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		refreshEloLabel(player)
	end)
end)

-- For players already in (Studio reload)
for _, p in ipairs(Players:GetPlayers()) do
	elo:Load(p)
	attachEloBillboard(p)
end

Players.PlayerRemoving:Connect(function(player)
	match:HandlePlayerLeaving(player)
	pad:SetBusy(player, false)
	elo:Save(player)
end)

-- Refresh the over-head Elo billboard whenever a match resolves.
Players.PlayerAdded:Connect(function() end) -- (no-op, retained to ensure module side effects)

-- Poll: cheap, runs at heartbeat, only updates when value changes.
local lastShownElo = setmetatable({}, { __mode = "k" })
game:GetService("RunService").Heartbeat:Connect(function()
	for _, p in ipairs(Players:GetPlayers()) do
		local cur = elo:Get(p)
		if cur ~= lastShownElo[p] then
			lastShownElo[p] = cur
			refreshEloLabel(p)
		end
	end
end)

Remotes.GetMyElo.OnServerInvoke = function(player)
	return elo:Get(player)
end

print("[SuperpowerShowdown] Server ready.")
