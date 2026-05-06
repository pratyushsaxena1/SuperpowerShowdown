-- Idempotent runtime lobby setup. Runs on every server start so the lobby
-- always has the correct layout/colors/lighting regardless of what's in
-- the saved place file. Studio runtime modifications via the command bar
-- don't always make it into the published place, so the safe approach is
-- to (re)build the lobby from code on boot.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local lobby = Workspace:WaitForChild("Lobby", 30)
if not lobby then
	warn("[LobbyBuilder] Lobby model not found in Workspace")
	return
end

-- ---------- Floor + spawn ----------

local floor = lobby:FindFirstChild("Floor")
if floor then
	floor.Anchored = true
	floor.CanCollide = true
	floor.Transparency = 0
	floor.Position = Vector3.new(0, 0, 0)
	floor.Size = Vector3.new(200, 2, 200)
	floor.Material = Enum.Material.Marble
	floor.Color = Color3.fromRGB(22, 22, 32)
end

local lobbySpawn = lobby:FindFirstChild("LobbySpawn")
if lobbySpawn and lobbySpawn:IsA("SpawnLocation") then
	lobbySpawn.Anchored = true
	lobbySpawn.CanCollide = true
	lobbySpawn.Enabled = true
	lobbySpawn.Neutral = true
	lobbySpawn.AllowTeamChangeOnTouch = false
	-- Sit flush on the floor: floor top y=1, spawn size y=1, center y=1.5.
	lobbySpawn.Position = Vector3.new(0, 1.5, -55)
	lobbySpawn.Size = Vector3.new(10, 1, 10)
	lobbySpawn.Material = Enum.Material.Neon
	lobbySpawn.Color = Color3.fromRGB(70, 230, 130)
	lobbySpawn.Transparency = 0.3
end

local returnSpawn = lobby:FindFirstChild("ReturnSpawn")
if returnSpawn then
	returnSpawn.Position = Vector3.new(0, 1.5, -35)
	returnSpawn.Material = Enum.Material.Neon
	returnSpawn.Color = Color3.fromRGB(160, 160, 200)
	returnSpawn.Transparency = 0.3
	returnSpawn.CanCollide = true
end

-- ---------- Walls (visible + solid) ----------

local walls = lobby:FindFirstChild("LobbyWalls")
if walls then
	for _, w in ipairs(walls:GetChildren()) do
		if w:IsA("BasePart") then
			w.Transparency = 0
			w.Material = Enum.Material.Slate
			w.Color = Color3.fromRGB(38, 38, 52)
			w.Reflectance = 0
			w.CanCollide = true
			w.Anchored = true
		end
	end
end

-- ---------- Ceiling ----------

local ceiling = lobby:FindFirstChild("Ceiling")
if not ceiling then
	ceiling = Instance.new("Part")
	ceiling.Name = "Ceiling"
	ceiling.Parent = lobby
end
ceiling.Anchored = true
ceiling.CanCollide = true
ceiling.Size = Vector3.new(202, 2, 202)
ceiling.Position = Vector3.new(0, 51, 0)
ceiling.Material = Enum.Material.Slate
ceiling.Color = Color3.fromRGB(40, 40, 55)
ceiling.Transparency = 0
ceiling.TopSurface = Enum.SurfaceType.Smooth
ceiling.BottomSurface = Enum.SurfaceType.Smooth

-- ---------- Ceiling lamps ----------

local oldLamps = lobby:FindFirstChild("CeilingLamps")
if oldLamps then oldLamps:Destroy() end
local lampFolder = Instance.new("Folder")
lampFolder.Name = "CeilingLamps"
lampFolder.Parent = lobby

-- 5x5 grid of ceiling lamps for even, bright coverage.
local lampPositions = {}
for _, x in ipairs({-80, -40, 0, 40, 80}) do
	for _, z in ipairs({-80, -40, 0, 40, 80}) do
		table.insert(lampPositions, {x=x, z=z})
	end
end
-- Note: Roblox caps active dynamic shadow-casting lights, and over-stuffing
-- the scene causes light pop-in/flicker. We rely on:
--   1. A high Lighting.Ambient + Brightness so the room is bright by default
--   2. Neon-material lamp panels (self-illuminate, no PointLight cost)
--   3. A sparse grid of non-shadow PointLights for accent color
for i, p in ipairs(lampPositions) do
	local lamp = Instance.new("Part")
	lamp.Name = "Lamp" .. i
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.Size = Vector3.new(7, 0.4, 7)
	lamp.Position = Vector3.new(p.x, 49.5, p.z)
	lamp.Material = Enum.Material.Neon
	lamp.Color = Color3.fromRGB(255, 245, 220)
	lamp.Transparency = 0.05
	lamp.TopSurface = Enum.SurfaceType.Smooth
	lamp.BottomSurface = Enum.SurfaceType.Smooth
	lamp.Parent = lampFolder

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 210)
	light.Brightness = 4
	light.Range = 60
	light.Shadows = false
	light.Parent = lamp
end

-- Wall sconces add bounce color to the walls. No shadows; small range.
local sconces = {
	{cf = CFrame.new(-99, 22, -50)}, {cf = CFrame.new(-99, 22, 0)}, {cf = CFrame.new(-99, 22, 50)},
	{cf = CFrame.new(99, 22, -50)},  {cf = CFrame.new(99, 22, 0)},  {cf = CFrame.new(99, 22, 50)},
	{cf = CFrame.new(-50, 22, -99)}, {cf = CFrame.new(0, 22, -99)}, {cf = CFrame.new(50, 22, -99)},
	{cf = CFrame.new(-50, 22, 99)},  {cf = CFrame.new(0, 22, 99)},  {cf = CFrame.new(50, 22, 99)},
}
for i, s in ipairs(sconces) do
	local sc = Instance.new("Part")
	sc.Name = "Sconce" .. i
	sc.Anchored = true
	sc.CanCollide = false
	sc.Size = Vector3.new(3, 1.5, 0.6)
	sc.CFrame = s.cf
	sc.Material = Enum.Material.Neon
	sc.Color = Color3.fromRGB(255, 220, 160)
	sc.Transparency = 0.1
	sc.Parent = lampFolder
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 220, 170)
	pl.Brightness = 2
	pl.Range = 22
	pl.Shadows = false
	pl.Parent = sc
end

-- ---------- Pad colors + pairing ----------
-- Front-row (DuelPad1..4) and back-row (DuelPad5..8) pads are paired by X
-- column so two friends can step on matching colors and know they'll be
-- matched together. The PadPair attribute is what MatchmakingService keys
-- off for direct-pair matchmaking.

local padDefs = {
	DuelPad1 = { color = Color3.fromRGB(235, 60, 80),  pair = "A" }, -- red pair
	DuelPad5 = { color = Color3.fromRGB(235, 60, 80),  pair = "A" },
	DuelPad2 = { color = Color3.fromRGB(245, 95, 175), pair = "B" }, -- pink pair
	DuelPad6 = { color = Color3.fromRGB(245, 95, 175), pair = "B" },
	DuelPad3 = { color = Color3.fromRGB(160, 230, 60), pair = "C" }, -- lime pair
	DuelPad7 = { color = Color3.fromRGB(160, 230, 60), pair = "C" },
	DuelPad4 = { color = Color3.fromRGB(80, 130, 250), pair = "D" }, -- blue pair
	DuelPad8 = { color = Color3.fromRGB(80, 130, 250), pair = "D" },
	AIPad1   = { color = Color3.fromRGB(70, 220, 110), pair = nil },
}
for name, def in pairs(padDefs) do
	local pad = lobby:FindFirstChild(name)
	if pad and pad:IsA("BasePart") then
		pad.Color = def.color
		pad.Material = Enum.Material.Neon
		pad:SetAttribute("BaseColor", def.color)
		pad:SetAttribute("PadPair", def.pair)
		pad.Position = Vector3.new(pad.Position.X, 1.9, pad.Position.Z)
		local light = pad:FindFirstChildWhichIsA("PointLight")
		if light then
			light.Color = def.color
			light.Brightness = 3
			light.Range = 16
		end
	end
end

-- ---------- Decorative platforms under the pads ----------

for _, n in ipairs({"DuelArenaBase","DuelArenaTrim_1","DuelArenaTrim_2","DuelArenaTrim_3","DuelArenaTrim_4","AIArenaBase","AIArenaTrim","AIArenaTrim_1","AIArenaTrim_2","AIArenaTrim_3","AIArenaTrim_4","DuelDivider"}) do
	local existing = lobby:FindFirstChild(n)
	if existing then existing:Destroy() end
end

local function makePart(name, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = lobby
	return p
end

makePart("DuelArenaBase", {
	Size = Vector3.new(80, 0.4, 50),
	Position = Vector3.new(0, 1.2, 5),
	Material = Enum.Material.SmoothPlastic,
	Color = Color3.fromRGB(28, 28, 38),
})

local trimColor = Color3.fromRGB(120, 200, 255)
local trims = {
	{Size=Vector3.new(80, 0.2, 0.4), Position=Vector3.new(0, 1.45, 30)},
	{Size=Vector3.new(80, 0.2, 0.4), Position=Vector3.new(0, 1.45, -20)},
	{Size=Vector3.new(0.4, 0.2, 50), Position=Vector3.new(-40, 1.45, 5)},
	{Size=Vector3.new(0.4, 0.2, 50), Position=Vector3.new(40, 1.45, 5)},
}
for i, t in ipairs(trims) do
	makePart("DuelArenaTrim_" .. i, {
		Size = t.Size, Position = t.Position,
		Material = Enum.Material.Neon, Color = trimColor,
	})
end

makePart("AIArenaBase", {
	Size = Vector3.new(20, 0.4, 20),
	Position = Vector3.new(0, 1.2, 55),
	Material = Enum.Material.SmoothPlastic,
	Color = Color3.fromRGB(28, 36, 28),
})
local aiTrims = {
	{Size=Vector3.new(20, 0.2, 0.4), Position=Vector3.new(0, 1.45, 65)},   -- back
	{Size=Vector3.new(20, 0.2, 0.4), Position=Vector3.new(0, 1.45, 45)},   -- front
	{Size=Vector3.new(0.4, 0.2, 20), Position=Vector3.new(-10, 1.45, 55)}, -- left
	{Size=Vector3.new(0.4, 0.2, 20), Position=Vector3.new(10, 1.45, 55)},  -- right
}
for i, t in ipairs(aiTrims) do
	makePart("AIArenaTrim_" .. i, {
		Size = t.Size, Position = t.Position,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(70, 220, 110),
	})
end

makePart("DuelDivider", {
	Size = Vector3.new(80, 0.15, 0.5),
	Position = Vector3.new(0, 1.45, 5),
	Material = Enum.Material.Neon,
	Color = Color3.fromRGB(80, 100, 140),
	Transparency = 0.3,
})

-- ---------- Indoor lighting ----------
-- Push Ambient very high so the entire interior is well-lit even when no
-- PointLight is in range. With shadows off on lamps + a strong ambient
-- floor, the light glitching/popping issue disappears because the engine
-- doesn't have to pick a small subset of dynamic shadow lights.

Lighting.Ambient = Color3.fromRGB(160, 155, 175)
Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 145)
Lighting.Brightness = 3
Lighting.ClockTime = 14
Lighting.GlobalShadows = false
Lighting.FogStart = 200
Lighting.FogEnd = 600
Lighting.FogColor = Color3.fromRGB(40, 40, 60)
Lighting.ExposureCompensation = 0.7

for _, c in ipairs(Lighting:GetChildren()) do
	if c:IsA("Sky") or c:IsA("Atmosphere") or c:IsA("Clouds") then
		c:Destroy()
	end
end

-- ---------- Arena template upgrades ----------

local ServerStorage = game:GetService("ServerStorage")
local arenaTemplates = ServerStorage:FindFirstChild("ArenaTemplates")
local arena = arenaTemplates and arenaTemplates:FindFirstChild("Arena")
if arena then
	-- Thicken walls and ceiling so a player flying with BodyVelocity can't
	-- phase through them in a single physics step, and push the inner faces
	-- out a bit so the arena feels less cramped while flying.
	local wallSpec = {
		WallNorth = { Position = Vector3.new(0, 40, -103), Size = Vector3.new(212, 80, 6) },
		WallSouth = { Position = Vector3.new(0, 40, 103),  Size = Vector3.new(212, 80, 6) },
		WallEast  = { Position = Vector3.new(103, 40, 0),  Size = Vector3.new(6, 80, 212) },
		WallWest  = { Position = Vector3.new(-103, 40, 0), Size = Vector3.new(6, 80, 212) },
	}
	for name, spec in pairs(wallSpec) do
		local w = arena:FindFirstChild(name)
		if w then
			w.Position = spec.Position
			w.Size = spec.Size
			w.Anchored = true
			w.CanCollide = true
		end
	end

	local ceilingP = arena:FindFirstChild("Ceiling")
	if ceilingP then
		ceilingP.Position = Vector3.new(0, 88, 0)
		ceilingP.Size = Vector3.new(212, 6, 212)
		ceilingP.Anchored = true
		ceilingP.CanCollide = true
	end

	local floorP = arena:FindFirstChild("Floor")
	if floorP then
		-- Slightly larger floor so the corners aren't open after the wall
		-- expansion.
		floorP.Position = Vector3.new(0, 0, 0)
		floorP.Size = Vector3.new(212, 2, 212)
		floorP.Anchored = true
		floorP.CanCollide = true
	end

	-- Declutter: remove rocks/barrels that just obstruct sight-lines and
	-- thin the crate count to four symmetrical cover pieces. Keeps the
	-- arena clean enough for fast 1v1 reads.
	for _, d in ipairs(arena:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = d.Name
			if n:find("UpperRock") or n:find("UpperBarrel")
				or n == "HeavyCrate7" or n == "HeavyCrate8" then
				d:Destroy()
			end
		end
	end

	-- Reposition the four remaining crates symmetrically as quarter-cover.
	local crateLayout = {
		HeavyCrate1 = Vector3.new(-30, 3, -30),
		HeavyCrate2 = Vector3.new( 30, 3, -30),
		HeavyCrate3 = Vector3.new(-30, 3,  30),
		HeavyCrate4 = Vector3.new( 30, 3,  30),
	}
	for name, pos in pairs(crateLayout) do
		local crate = arena:FindFirstChild(name)
		if crate and crate:IsA("BasePart") then
			crate.Position = pos
			crate.Size = Vector3.new(6, 6, 6)
			crate.Anchored = true
			crate.CanCollide = true
			crate.Material = Enum.Material.WoodPlanks
			crate.Color = Color3.fromRGB(110, 80, 50)
		end
	end

	-- Center pillar: a single tall cover piece in the middle for high-stakes
	-- duel reads. Idempotent on rerun.
	local oldPillar = arena:FindFirstChild("CenterPillar")
	if oldPillar then oldPillar:Destroy() end
	local pillar = Instance.new("Part")
	pillar.Name = "CenterPillar"
	pillar.Anchored = true
	pillar.CanCollide = true
	pillar.Size = Vector3.new(6, 12, 6)
	pillar.Position = Vector3.new(0, 7, 0)
	pillar.Material = Enum.Material.Slate
	pillar.Color = Color3.fromRGB(60, 60, 75)
	pillar.TopSurface = Enum.SurfaceType.Smooth
	pillar.BottomSurface = Enum.SurfaceType.Smooth
	pillar.Parent = arena
	-- Glowing accent strip on top of the pillar so it reads as intentional.
	local pillarTop = Instance.new("Part")
	pillarTop.Name = "CenterPillarTop"
	pillarTop.Anchored = true
	pillarTop.CanCollide = false
	pillarTop.Size = Vector3.new(6.4, 0.4, 6.4)
	pillarTop.Position = Vector3.new(0, 13.2, 0)
	pillarTop.Material = Enum.Material.Neon
	pillarTop.Color = Color3.fromRGB(255, 230, 130)
	pillarTop.Transparency = 0.2
	pillarTop.Parent = arena

	for _, d in ipairs(arena:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Ceiling" then
				d.Transparency = 0
				d.Material = Enum.Material.Slate
				d.Color = Color3.fromRGB(35, 35, 50)
			elseif d.Name:find("Wall") then
				d.Transparency = 0
				d.Material = Enum.Material.Slate
				d.Color = Color3.fromRGB(40, 40, 55)
			elseif d.Name == "Floor" then
				d.Material = Enum.Material.Marble
				d.Color = Color3.fromRGB(28, 28, 40)
			elseif d.Name == "Lamp" then
				d.Material = Enum.Material.Neon
				d.Transparency = 0.05
				local pl = d:FindFirstChildWhichIsA("PointLight")
				if pl then
					pl.Brightness = 4
					pl.Range = 55
					pl.Shadows = false
				end
			end
		end
	end

	-- Add an extra grid of ceiling lamps so the arena reads as well-lit.
	local extraLampFolder = arena:FindFirstChild("ExtraLamps")
	if extraLampFolder then extraLampFolder:Destroy() end
	extraLampFolder = Instance.new("Folder")
	extraLampFolder.Name = "ExtraLamps"
	extraLampFolder.Parent = arena

	for _, x in ipairs({-60, -20, 20, 60}) do
		for _, z in ipairs({-60, -20, 20, 60}) do
			local lamp = Instance.new("Part")
			lamp.Name = "ExtraLamp"
			lamp.Anchored = true
			lamp.CanCollide = false
			lamp.Size = Vector3.new(6, 0.4, 6)
			lamp.Position = Vector3.new(x, 78.5, z)
			lamp.Material = Enum.Material.Neon
			lamp.Color = Color3.fromRGB(255, 240, 210)
			lamp.Transparency = 0.05
			lamp.TopSurface = Enum.SurfaceType.Smooth
			lamp.BottomSurface = Enum.SurfaceType.Smooth
			lamp.Parent = extraLampFolder
			local pl = Instance.new("PointLight")
			pl.Color = Color3.fromRGB(255, 240, 210)
			pl.Brightness = 3
			pl.Range = 45
			pl.Shadows = false
			pl.Parent = lamp
		end
	end
end

print("[LobbyBuilder] Lobby setup complete")
