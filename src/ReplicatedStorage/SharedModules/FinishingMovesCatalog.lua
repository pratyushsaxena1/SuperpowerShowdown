-- Catalog of "Finishing Moves" — short scripted sequences (~2-2.5s) that
-- play on the killed character's body when the killer has the matching
-- cosmetic equipped. Distinct from KillEffects: these animate the victim
-- itself (rising, sinking, spinning, exploding), so they read as a finisher
-- rather than just a particle burst.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local FinishingMovesCatalog = {}

FinishingMovesCatalog.Order = { "Tombstone", "RocketLaunch", "BlackHole", "MeteorStrike" }

FinishingMovesCatalog.Moves = {
	Tombstone = {
		name = "Tombstone",
		description = "A weathered gravestone rises with a cross and dirt mound.",
		accentColor = Color3.fromRGB(170, 170, 180),
		robuxPrice = 50, coinPrice = 12000,
	},
	RocketLaunch = {
		name = "Rocket Launch",
		description = "The body rockets skyward in a column of fire and smoke.",
		accentColor = Color3.fromRGB(255, 130, 60),
		robuxPrice = 50, coinPrice = 12000,
	},
	BlackHole = {
		name = "Black Hole",
		description = "A swirling void with orbiting light pulls the body in.",
		accentColor = Color3.fromRGB(180, 80, 240),
		robuxPrice = 50, coinPrice = 12000,
	},
	MeteorStrike = {
		name = "Meteor Strike",
		description = "A burning meteor crashes down, scattering debris.",
		accentColor = Color3.fromRGB(255, 90, 50),
		robuxPrice = 50, coinPrice = 12000,
	},
}

local FIRE_TEX = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do p[k] = v end
	return p
end

local function tween(inst, t, props, style, dir)
	return TweenService:Create(inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
end

local function getOrigin(victimChar)
	local hrp = victimChar:FindFirstChild("HumanoidRootPart")
		or victimChar:FindFirstChildWhichIsA("BasePart")
	return hrp and hrp.Position
end

-- Single anchored cube sized to a body. Used by RocketLaunch and BlackHole
-- as a stand-in for the dying character (the real character is being
-- cleaned up by the Humanoid death pipeline; tweening the originals
-- yanks parts away mid-animation).
local function makeBodyProxy(pos, color, material)
	local proxy = newPart({
		Name = "FinisherProxy",
		Size = Vector3.new(2, 5, 1),
		Material = material or Enum.Material.SmoothPlastic,
		Color = color or Color3.fromRGB(180, 180, 195),
		CFrame = CFrame.new(pos),
		Transparency = 0.05,
	})
	return proxy
end

-- Gravestone rises from the ground with a cross + dirt mound + ghost wisp.
local function playTombstone(victim)
	local pos = getOrigin(victim); if not pos then return end
	local groundY = pos.Y - 2.6

	-- Dirt mound: 4 brown lumps clustered around the stone base.
	for i = 1, 4 do
		local angle = (i - 1) * (math.pi * 0.5) + math.random() * 0.3
		local off = 1 + math.random() * 0.6
		local lump = newPart({
			Material = Enum.Material.Ground,
			Color = Color3.fromRGB(70, 50, 35),
			Size = Vector3.new(1.4, 0.05, 1.4),
			CFrame = CFrame.new(pos.X + math.cos(angle) * off,
				groundY + 0.1, pos.Z + math.sin(angle) * off),
		})
		lump.Parent = workspace
		Debris:AddItem(lump, 3)
		tween(lump, 0.5, { Size = Vector3.new(1.4, 0.6, 1.4),
			CFrame = lump.CFrame + Vector3.new(0, 0.25, 0) },
			Enum.EasingStyle.Back, Enum.EasingDirection.Out):Play()
	end

	-- Main slab (rises from below).
	local slab = newPart({
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(115, 115, 125),
		Size = Vector3.new(3, 0.3, 0.7),
		CFrame = CFrame.new(pos.X, groundY - 4, pos.Z),
	})
	slab.Parent = workspace
	Debris:AddItem(slab, 3)
	tween(slab, 1.0,
		{ Size = Vector3.new(3, 4.2, 0.7),
		  CFrame = CFrame.new(pos.X, groundY + 1.6, pos.Z) },
		Enum.EasingStyle.Back, Enum.EasingDirection.Out):Play()

	-- Cross on top: vertical bar + horizontal bar. Fade-in slightly delayed
	-- so it appears once the slab's top is visible.
	task.delay(0.6, function()
		if not slab.Parent then return end
		local top = slab.Position + Vector3.new(0, 2.4, 0)
		local crossV = newPart({
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(95, 95, 105),
			Size = Vector3.new(0.35, 1.6, 0.4),
			CFrame = CFrame.new(top), Transparency = 1,
		})
		crossV.Parent = workspace
		Debris:AddItem(crossV, 3)
		local crossH = newPart({
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(95, 95, 105),
			Size = Vector3.new(1.2, 0.35, 0.4),
			CFrame = CFrame.new(top.X, top.Y + 0.2, top.Z), Transparency = 1,
		})
		crossH.Parent = workspace
		Debris:AddItem(crossH, 3)
		tween(crossV, 0.3, { Transparency = 0 }):Play()
		tween(crossH, 0.3, { Transparency = 0 }):Play()
	end)

	-- Ghost wisp particles trail upward.
	local at = Instance.new("Attachment")
	at.WorldCFrame = CFrame.new(pos.X, groundY + 1, pos.Z)
	at.Parent = workspace.Terrain
	Debris:AddItem(at, 3)
	local wisp = Instance.new("ParticleEmitter")
	wisp.Texture = SMOKE_TEX
	wisp.Color = ColorSequence.new(Color3.fromRGB(220, 230, 245))
	wisp.Size = NumberSequence.new(2, 0.5)
	wisp.Lifetime = NumberRange.new(1.2, 1.8)
	wisp.Speed = NumberRange.new(3, 5)
	wisp.SpreadAngle = Vector2.new(8, 8)
	wisp.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	wisp.LightEmission = 0.6
	wisp.Rate = 12
	wisp.Parent = at
	task.delay(2, function() wisp.Rate = 0 end)
end

-- Body launches up on a column of flame + smoke trail, with multi-stage
-- ignition: ground-level puff, ascent burn, and a fading apex flash.
local function playRocketLaunch(victim)
	local pos = getOrigin(victim); if not pos then return end
	local groundY = pos.Y - 2.6
	local flame = Color3.fromRGB(255, 150, 40)

	-- Ignition flash at ground level.
	local flash = newPart({
		Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 220, 120),
		Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(pos.X, groundY + 0.5, pos.Z),
		Transparency = 0,
	})
	flash.Parent = workspace
	Debris:AddItem(flash, 0.6)
	tween(flash, 0.5, { Size = Vector3.new(8, 8, 8), Transparency = 1 }):Play()

	-- Smoke ground puff.
	local puffAt = Instance.new("Attachment")
	puffAt.WorldCFrame = CFrame.new(pos.X, groundY + 0.5, pos.Z)
	puffAt.Parent = workspace.Terrain
	Debris:AddItem(puffAt, 2.5)
	local puff = Instance.new("ParticleEmitter")
	puff.Texture = SMOKE_TEX
	puff.Color = ColorSequence.new(Color3.fromRGB(80, 70, 65))
	puff.Size = NumberSequence.new(4, 8)
	puff.Lifetime = NumberRange.new(1.0, 1.6)
	puff.Speed = NumberRange.new(4, 9)
	puff.SpreadAngle = Vector2.new(180, 180)
	puff.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	puff.Rate = 0; puff.Parent = puffAt
	puff:Emit(30)

	-- The body proxy.
	local proxy = makeBodyProxy(pos, Color3.fromRGB(180, 180, 195))
	proxy.Parent = workspace
	Debris:AddItem(proxy, 2.4)

	-- Two stacked particle attachments under the body for the long flame
	-- trail. Rate goes high then drops once the body's near apex.
	local trailAt = Instance.new("Attachment")
	trailAt.Position = Vector3.new(0, -2.5, 0)
	trailAt.Parent = proxy
	local trail = Instance.new("ParticleEmitter")
	trail.Texture = FIRE_TEX
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 180)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 40, 20)),
	})
	trail.Size = NumberSequence.new(3, 0.3)
	trail.Lifetime = NumberRange.new(0.3, 0.7)
	trail.Speed = NumberRange.new(20, 35)
	trail.SpreadAngle = Vector2.new(15, 15)
	trail.Rotation = NumberRange.new(0, 360)
	trail.RotSpeed = NumberRange.new(-200, 200)
	trail.Rate = 250; trail.LightEmission = 1
	trail.Parent = trailAt

	local smokeTrail = Instance.new("ParticleEmitter")
	smokeTrail.Texture = SMOKE_TEX
	smokeTrail.Color = ColorSequence.new(Color3.fromRGB(50, 40, 38))
	smokeTrail.Size = NumberSequence.new(2.5, 6)
	smokeTrail.Lifetime = NumberRange.new(1.0, 1.8)
	smokeTrail.Speed = NumberRange.new(2, 5)
	smokeTrail.SpreadAngle = Vector2.new(40, 40)
	smokeTrail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeTrail.Rate = 60; smokeTrail.Parent = trailAt

	local light = Instance.new("PointLight")
	light.Color = flame; light.Range = 18; light.Brightness = 5; light.Shadows = false
	light.Parent = proxy

	-- Ascend with a slight wobble for character (rocket isn't perfectly stable).
	tween(proxy, 1.8, {
		CFrame = CFrame.new(pos + Vector3.new(0, 180, 0))
			* CFrame.Angles(math.rad(8), 0, math.rad(-5)),
	}, Enum.EasingStyle.Quad, Enum.EasingDirection.In):Play()
	-- Fade body near the top.
	task.delay(1.4, function()
		if proxy.Parent then
			tween(proxy, 0.4, { Transparency = 1 }):Play()
			trail.Rate = 0; smokeTrail.Rate = 0
		end
	end)
end

-- Visible swirling void: large neon-black sphere + 3 orbiting bright streaks
-- + particles being PULLED INWARD toward the center. Body proxy spirals in
-- and shrinks. Final implosion flash.
local function playBlackHole(victim)
	local pos = getOrigin(victim); if not pos then return end
	local voidColor = Color3.fromRGB(8, 0, 14)
	local rim = Color3.fromRGB(200, 90, 255)
	local DURATION = 2.0

	-- Core void sphere, dark with a faint neon glow.
	local core = newPart({
		Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
		Color = voidColor, Size = Vector3.new(0.5, 0.5, 0.5),
		CFrame = CFrame.new(pos), Transparency = 0,
	})
	core.Parent = workspace
	Debris:AddItem(core, DURATION + 0.3)
	tween(core, 0.5, { Size = Vector3.new(8, 8, 8) },
		Enum.EasingStyle.Quad, Enum.EasingDirection.Out):Play()

	-- Bright outer rim sphere (slightly larger, ForceField for shimmer).
	local outer = newPart({
		Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField,
		Color = rim, Size = Vector3.new(0.5, 0.5, 0.5),
		CFrame = CFrame.new(pos), Transparency = 0.3,
	})
	outer.Parent = workspace
	Debris:AddItem(outer, DURATION + 0.3)
	tween(outer, 0.5, { Size = Vector3.new(10, 10, 10) }):Play()

	-- 3 orbital streaks driven by RenderStepped-equivalent: a per-frame
	-- update on the server's Heartbeat. Each streak is a thin neon block
	-- whose CFrame spins around the core on a tilted axis. Disconnect on
	-- DURATION so the loop dies before parts are debris-cleaned.
	local orbits = {}
	for i = 1, 3 do
		local seg = newPart({
			Material = Enum.Material.Neon,
			Color = rim,
			Size = Vector3.new(0.4, 0.4, 6),
			CFrame = CFrame.new(pos), Transparency = 0,
		})
		seg.Parent = workspace
		Debris:AddItem(seg, DURATION + 0.3)
		table.insert(orbits, {
			part = seg,
			tilt = (i - 1) * math.rad(60),
			phase = i * math.rad(45),
			radius = 5 + i * 0.5,
		})
	end
	local startT = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startT
		if t > DURATION then conn:Disconnect(); return end
		for _, o in ipairs(orbits) do
			if not o.part.Parent then conn:Disconnect(); return end
			local angle = o.phase + t * 12 -- rad/s
			local r = o.radius * (1 - t / DURATION) -- shrink with the void
			local local_pos = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
			-- Tilt the orbit plane around X so the three streaks travel
			-- on differently-oriented circles instead of stacking flat.
			local rot = CFrame.Angles(o.tilt, 0, 0)
			local world = CFrame.new(pos) * rot * CFrame.new(local_pos)
			o.part.CFrame = world * CFrame.Angles(0, math.pi * 0.5 - angle, 0)
		end
	end)

	-- Particles getting pulled INWARD: spawn on a sphere shell and tween
	-- them toward the center. Cheaper than ParticleEmitter Acceleration
	-- math and lets us guarantee they actually converge on the void.
	for i = 1, 28 do
		task.delay(math.random() * 0.4, function()
			if not core.Parent then return end
			local theta = math.random() * math.pi * 2
			local phi = math.acos(2 * math.random() - 1)
			local r0 = 12
			local startPos = pos + Vector3.new(
				r0 * math.sin(phi) * math.cos(theta),
				r0 * math.sin(phi) * math.sin(theta) * 0.6,
				r0 * math.cos(phi)
			)
			local mote = newPart({
				Shape = Enum.PartType.Ball,
				Material = Enum.Material.Neon, Color = rim,
				Size = Vector3.new(0.5, 0.5, 0.5),
				CFrame = CFrame.new(startPos), Transparency = 0.1,
			})
			mote.Parent = workspace
			Debris:AddItem(mote, 1.4)
			tween(mote, 0.9 + math.random() * 0.4, {
				CFrame = CFrame.new(pos), Size = Vector3.new(0.05, 0.05, 0.05),
				Transparency = 0.5,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In):Play()
		end)
	end

	-- Body proxy spirals into the core while shrinking + drifting in.
	local proxy = makeBodyProxy(pos, Color3.fromRGB(160, 160, 180))
	proxy.Parent = workspace
	Debris:AddItem(proxy, DURATION + 0.3)
	task.spawn(function()
		local sT = os.clock()
		while proxy.Parent and (os.clock() - sT) < DURATION * 0.85 do
			local t = (os.clock() - sT) / DURATION
			local r = 4 * (1 - t)
			local angle = t * 20
			local p = pos + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
			proxy.CFrame = CFrame.new(p)
				* CFrame.Angles(0, angle * 2, 0)
			proxy.Size = Vector3.new(2, 5, 1) * (1 - t)
			proxy.Transparency = math.min(1, 0.05 + t * 0.6)
			RunService.Heartbeat:Wait()
		end
	end)

	-- Implosion flash + fade-out at the end.
	task.delay(DURATION, function()
		local flash = newPart({
			Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 180, 255),
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(pos), Transparency = 0,
		})
		flash.Parent = workspace
		Debris:AddItem(flash, 0.6)
		tween(flash, 0.5, { Size = Vector3.new(20, 20, 20), Transparency = 1 }):Play()
		if core.Parent then tween(core, 0.3, { Transparency = 1 }):Play() end
		if outer.Parent then tween(outer, 0.3, { Transparency = 1 }):Play() end
	end)

	local light = Instance.new("PointLight")
	light.Color = rim; light.Range = 28; light.Brightness = 4; light.Shadows = false
	light.Parent = core
end

-- Meteor crashes from the sky with a flame trail, lands with a massive
-- impact flash, and scatters radial debris + a smoke pillar.
local function playMeteorStrike(victim)
	local pos = getOrigin(victim); if not pos then return end
	local groundY = pos.Y - 2.6
	local flame = Color3.fromRGB(255, 130, 40)

	-- The meteor itself: dark stone ball with a fire tail attachment.
	local meteor = newPart({
		Name = "Meteor", Shape = Enum.PartType.Ball,
		Material = Enum.Material.Slate, Color = Color3.fromRGB(45, 28, 22),
		Size = Vector3.new(7, 7, 7),
		CFrame = CFrame.new(pos.X - 30, pos.Y + 90, pos.Z - 20),
	})
	meteor.Parent = workspace
	Debris:AddItem(meteor, 2.5)

	local tailAt = Instance.new("Attachment")
	tailAt.Parent = meteor
	local tail = Instance.new("ParticleEmitter")
	tail.Texture = FIRE_TEX
	tail.Color = ColorSequence.new(flame)
	tail.Size = NumberSequence.new(6, 0.6)
	tail.Lifetime = NumberRange.new(0.3, 0.7)
	tail.Speed = NumberRange.new(0, 2)
	tail.SpreadAngle = Vector2.new(20, 20)
	tail.Rate = 350; tail.LightEmission = 1; tail.Parent = tailAt

	local smokeTail = Instance.new("ParticleEmitter")
	smokeTail.Texture = SMOKE_TEX
	smokeTail.Color = ColorSequence.new(Color3.fromRGB(50, 40, 38))
	smokeTail.Size = NumberSequence.new(4, 8)
	smokeTail.Lifetime = NumberRange.new(0.8, 1.4)
	smokeTail.Speed = NumberRange.new(0, 2)
	smokeTail.SpreadAngle = Vector2.new(20, 20)
	smokeTail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeTail.Rate = 80; smokeTail.Parent = tailAt

	local meteorLight = Instance.new("PointLight")
	meteorLight.Color = flame; meteorLight.Range = 24; meteorLight.Brightness = 6
	meteorLight.Shadows = false; meteorLight.Parent = meteor

	-- Plummet onto the body in a shallow arc.
	tween(meteor, 0.7,
		{ CFrame = CFrame.new(pos.X, groundY + 0.5, pos.Z) },
		Enum.EasingStyle.Quad, Enum.EasingDirection.In):Play()

	task.delay(0.7, function()
		if not meteor.Parent then return end
		tail.Rate = 0; smokeTail.Rate = 0

		-- Impact flash.
		local flash = newPart({
			Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 220, 130),
			Size = Vector3.new(3, 3, 3),
			CFrame = CFrame.new(pos.X, groundY + 1, pos.Z), Transparency = 0,
		})
		flash.Parent = workspace
		Debris:AddItem(flash, 1)
		tween(flash, 0.7, { Size = Vector3.new(28, 28, 28), Transparency = 1 }):Play()

		-- Radial fire ring.
		local ring = newPart({
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Neon, Color = flame,
			Size = Vector3.new(0.4, 1, 1),
			CFrame = CFrame.new(pos.X, groundY + 0.1, pos.Z)
				* CFrame.Angles(0, 0, math.pi * 0.5),
		})
		ring.Parent = workspace
		Debris:AddItem(ring, 1.4)
		tween(ring, 1.2, { Size = Vector3.new(0.4, 26, 26), Transparency = 1 }):Play()

		-- 10 debris chunks fly out radially with rotation, then drop.
		for i = 1, 10 do
			local angle = (i - 1) * (math.pi * 2 / 10) + math.random() * 0.2
			local outward = 9 + math.random() * 6
			local chunk = newPart({
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(60, 40, 32),
				Size = Vector3.new(0.8 + math.random() * 0.6,
					0.6 + math.random() * 0.5,
					0.8 + math.random() * 0.6),
				CFrame = CFrame.new(pos.X, groundY + 1, pos.Z),
			})
			chunk.Parent = workspace
			Debris:AddItem(chunk, 1.6)
			local apex = Vector3.new(pos.X + math.cos(angle) * outward * 0.5,
				groundY + 5 + math.random() * 3,
				pos.Z + math.sin(angle) * outward * 0.5)
			local landing = Vector3.new(pos.X + math.cos(angle) * outward,
				groundY + 0.4, pos.Z + math.sin(angle) * outward)
			tween(chunk, 0.35, {
				CFrame = CFrame.new(apex)
					* CFrame.Angles(math.random() * math.pi, math.random() * math.pi, 0),
			}):Play()
			task.delay(0.35, function()
				if chunk.Parent then
					tween(chunk, 0.6, {
						CFrame = CFrame.new(landing)
							* CFrame.Angles(math.random() * math.pi * 2,
								math.random() * math.pi * 2, 0),
					}, Enum.EasingStyle.Quad, Enum.EasingDirection.In):Play()
				end
			end)
		end

		-- Crater rim: 4 angled flat slabs forming a low ring.
		for i = 1, 6 do
			local angle = (i - 1) * (math.pi / 3)
			local rim = newPart({
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(50, 35, 28),
				Size = Vector3.new(2.5, 0.4, 1.4),
				CFrame = CFrame.new(pos.X + math.cos(angle) * 4.5,
					groundY + 0.2,
					pos.Z + math.sin(angle) * 4.5)
					* CFrame.Angles(0, -angle, math.rad(15)),
			})
			rim.Parent = workspace
			Debris:AddItem(rim, 2)
			tween(rim, 1.6, { Transparency = 1 }):Play()
		end

		-- Smoke pillar rising from the impact.
		local pillarAt = Instance.new("Attachment")
		pillarAt.WorldCFrame = CFrame.new(pos.X, groundY + 0.5, pos.Z)
		pillarAt.Parent = workspace.Terrain
		Debris:AddItem(pillarAt, 2.2)
		local pillar = Instance.new("ParticleEmitter")
		pillar.Texture = SMOKE_TEX
		pillar.Color = ColorSequence.new(Color3.fromRGB(60, 50, 45))
		pillar.Size = NumberSequence.new(4, 9)
		pillar.Lifetime = NumberRange.new(1.4, 2.0)
		pillar.Speed = NumberRange.new(8, 14)
		pillar.SpreadAngle = Vector2.new(15, 15)
		pillar.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		pillar.Rate = 80; pillar.Parent = pillarAt
		task.delay(1.4, function() pillar.Rate = 0 end)

		-- Fade meteor as it sinks/burns out.
		tween(meteor, 0.6, { Transparency = 1 },
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out):Play()
		tween(meteorLight, 0.6, { Brightness = 0 }):Play()
	end)
end

local PLAYERS = {
	Tombstone = playTombstone,
	RocketLaunch = playRocketLaunch,
	BlackHole = playBlackHole,
	MeteorStrike = playMeteorStrike,
}

function FinishingMovesCatalog.apply(victimChar, moveName)
	if not victimChar then return end
	local fn = PLAYERS[moveName]
	if not fn then return end
	-- pcall so a single broken finisher can't throw inside the death
	-- pipeline and block ELO updates / coin awards for the match.
	pcall(fn, victimChar)
end

function FinishingMovesCatalog.exists(name)
	return FinishingMovesCatalog.Moves[name] ~= nil
end

function FinishingMovesCatalog.priceOf(name)
	local def = FinishingMovesCatalog.Moves[name]
	return def and def.robuxPrice or 0, def and def.coinPrice or 0
end

return FinishingMovesCatalog
