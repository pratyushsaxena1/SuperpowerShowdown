-- Catalog of "Kill Effects" — visual flair fired at the victim's body
-- when their killer has the matching cosmetic equipped. Each effect is
-- short-lived (~1.5–2s), parented to workspace, and self-cleans via
-- Debris so respawn cleanup doesn't have to track them.
--
-- Visual goals: every effect must read DIFFERENT at a glance — not "ring
-- + sparkles in a different color". Each one combines several primitives
-- (crater/cracks, pillar of fire, crystal spikes, lightning bolts,
-- coin shower) so they read like distinct concepts, not palette swaps.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local KillEffectsCatalog = {}

KillEffectsCatalog.Order = { "Shockwave", "Inferno", "Frostbite", "Voltage", "GoldRush" }

KillEffectsCatalog.Effects = {
	Shockwave = {
		name = "Shockwave",
		description = "A concussive ring of force erupts from the fallen.",
		accentColor = Color3.fromRGB(180, 220, 255),
		robuxPrice = 35, coinPrice = 7500,
	},
	Inferno = {
		name = "Inferno",
		description = "A roaring pillar of fire engulfs the body.",
		accentColor = Color3.fromRGB(255, 130, 60),
		robuxPrice = 35, coinPrice = 7500,
	},
	Frostbite = {
		name = "Frostbite",
		description = "Jagged ice crystals erupt from the killing ground.",
		accentColor = Color3.fromRGB(150, 230, 255),
		robuxPrice = 35, coinPrice = 7500,
	},
	Voltage = {
		name = "Voltage",
		description = "Crackling violet lightning forks across the body.",
		accentColor = Color3.fromRGB(225, 90, 255),
		robuxPrice = 35, coinPrice = 7500,
	},
	GoldRush = {
		name = "Gold Rush",
		description = "A torrent of golden coins explodes outward.",
		accentColor = Color3.fromRGB(255, 220, 100),
		robuxPrice = 35, coinPrice = 7500,
	},
}

local FIRE_TEX = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"

-- Local helpers. newPart returns an anchored, non-colliding part with
-- sensible defaults so each effect's body code is just position/size/color.
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
		or victimChar:FindFirstChild("Torso")
		or victimChar:FindFirstChildWhichIsA("BasePart")
	return hrp and hrp.Position
end

-- Concussive: floor crater ring + radial cracks + huge transparent
-- distortion sphere + brief light pulse. Reads as a physical impact.
local function playShockwave(victim)
	local pos = getOrigin(victim); if not pos then return end
	local groundY = pos.Y - 2.6
	local accent = Color3.fromRGB(220, 240, 255)

	local ring = newPart({
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon, Color = accent,
		Size = Vector3.new(0.4, 1, 1),
		CFrame = CFrame.new(pos.X, groundY, pos.Z) * CFrame.Angles(0, 0, math.pi * 0.5),
		Transparency = 0.1,
	})
	ring.Parent = workspace
	Debris:AddItem(ring, 1.6)
	tween(ring, 1.5, { Size = Vector3.new(0.4, 22, 22), Transparency = 1 }):Play()

	-- 8 radial cracks racing outward along the ground.
	for i = 1, 8 do
		local angle = (i - 1) * math.pi / 4 + (math.random() - 0.5) * 0.25
		local crack = newPart({
			Material = Enum.Material.Neon, Color = accent,
			Size = Vector3.new(0.25, 0.05, 1),
			CFrame = CFrame.new(pos.X, groundY + 0.05, pos.Z)
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, 0, -0.5),
			Transparency = 0,
		})
		crack.Parent = workspace
		Debris:AddItem(crack, 1.6)
		tween(crack, 1.4,
			{ Size = Vector3.new(0.25, 0.05, 16), Transparency = 1 }
		):Play()
	end

	-- Air-distortion sphere (ForceField material reads as shimmer).
	local dist = newPart({
		Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(255, 255, 255),
		Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(pos), Transparency = 0.4,
	})
	dist.Parent = workspace
	Debris:AddItem(dist, 1.5)
	tween(dist, 1.2, { Size = Vector3.new(36, 36, 36), Transparency = 1 }):Play()

	-- Particle burst + light pulse from a temp attachment.
	local at = Instance.new("Attachment")
	at.WorldCFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
	at.Parent = workspace.Terrain
	Debris:AddItem(at, 1.6)

	local burst = Instance.new("ParticleEmitter")
	burst.Texture = SMOKE_TEX
	burst.Color = ColorSequence.new(Color3.fromRGB(220, 230, 250))
	burst.Size = NumberSequence.new(2.8, 0.2)
	burst.Lifetime = NumberRange.new(0.5, 1.0)
	burst.Speed = NumberRange.new(8, 22)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rotation = NumberRange.new(0, 360)
	burst.RotSpeed = NumberRange.new(-180, 180)
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.LightEmission = 0.4
	burst.Rate = 0
	burst.Parent = at
	burst:Emit(45)

	local light = Instance.new("PointLight")
	light.Color = accent; light.Range = 22; light.Brightness = 5
	light.Shadows = false; light.Parent = at
	tween(light, 1.0, { Brightness = 0 }):Play()
end

-- Pillar of fire rising 22 studs. Multiple emitters along the column +
-- a charred ground ring + a smoke pillar ascending behind the flame.
local function playInferno(victim)
	local pos = getOrigin(victim); if not pos then return end
	local groundY = pos.Y - 2.6
	local fire = Color3.fromRGB(255, 150, 50)

	-- Charred ground ring fades in then out.
	local scorch = newPart({
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Slate, Color = Color3.fromRGB(30, 18, 14),
		Size = Vector3.new(0.2, 14, 14),
		CFrame = CFrame.new(pos.X, groundY + 0.05, pos.Z)
			* CFrame.Angles(0, 0, math.pi * 0.5),
		Transparency = 1,
	})
	scorch.Parent = workspace
	Debris:AddItem(scorch, 2)
	tween(scorch, 0.3, { Transparency = 0.1 }):Play()
	task.delay(1.2, function() tween(scorch, 0.6, { Transparency = 1 }):Play() end)

	-- Pillar core (neon orange cylinder rising from ground).
	local pillar = newPart({
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon, Color = fire,
		Size = Vector3.new(1, 4, 4),
		CFrame = CFrame.new(pos.X, groundY + 2, pos.Z),
		Transparency = 0.2,
	})
	pillar.Parent = workspace
	Debris:AddItem(pillar, 2)
	tween(pillar, 0.4,
		{ Size = Vector3.new(22, 4.5, 4.5), CFrame = CFrame.new(pos.X, groundY + 11, pos.Z),
		  Transparency = 0.4 }
	):Play()
	task.delay(0.8, function()
		tween(pillar, 0.9, { Transparency = 1, Size = Vector3.new(22, 1, 1) }):Play()
	end)

	-- Three fire ParticleEmitters stacked along the pillar height.
	for i = 0, 2 do
		local at = Instance.new("Attachment")
		at.WorldCFrame = CFrame.new(pos.X, groundY + 1 + i * 7, pos.Z)
		at.Parent = workspace.Terrain
		Debris:AddItem(at, 2)

		local fp = Instance.new("ParticleEmitter")
		fp.Texture = FIRE_TEX
		fp.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 180)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 40, 20)),
		})
		fp.Size = NumberSequence.new(4 - i * 0.5, 0.2)
		fp.Lifetime = NumberRange.new(0.4, 0.8)
		fp.Speed = NumberRange.new(12, 20)
		fp.SpreadAngle = Vector2.new(20, 20)
		fp.Rotation = NumberRange.new(0, 360)
		fp.RotSpeed = NumberRange.new(-200, 200)
		fp.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 1),
		})
		fp.LightEmission = 1
		fp.Rate = 200
		fp.Parent = at
		task.delay(1.0, function() fp.Rate = 0 end)
	end

	-- Smoke pillar rising afterwards (slower particles, dark color).
	local smokeAt = Instance.new("Attachment")
	smokeAt.WorldCFrame = CFrame.new(pos.X, groundY + 4, pos.Z)
	smokeAt.Parent = workspace.Terrain
	Debris:AddItem(smokeAt, 2.4)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEX
	smoke.Color = ColorSequence.new(Color3.fromRGB(50, 40, 38))
	smoke.Size = NumberSequence.new(3, 7)
	smoke.Lifetime = NumberRange.new(1.0, 1.6)
	smoke.Speed = NumberRange.new(6, 10)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Rate = 60
	smoke.Parent = smokeAt
	task.delay(1.6, function() smoke.Rate = 0 end)

	local light = Instance.new("PointLight")
	light.Color = fire; light.Range = 24; light.Brightness = 6; light.Shadows = false
	light.Parent = pillar
	tween(light, 2, { Brightness = 0 }):Play()
end

-- Crystalline spikes erupt radially from the kill point, pause, then
-- shatter outward into a mist.
local function playFrostbite(victim)
	local pos = getOrigin(victim); if not pos then return end
	local groundY = pos.Y - 2.6
	local ice = Color3.fromRGB(180, 235, 255)

	-- Frosted ring on ground.
	local ring = newPart({
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Glass, Color = ice,
		Size = Vector3.new(0.2, 14, 14),
		CFrame = CFrame.new(pos.X, groundY + 0.05, pos.Z)
			* CFrame.Angles(0, 0, math.pi * 0.5),
		Transparency = 0.3, Reflectance = 0.4,
	})
	ring.Parent = workspace
	Debris:AddItem(ring, 2)
	tween(ring, 1.6, { Transparency = 1 }):Play()

	-- 7 ice crystal spikes jutting outward and upward.
	local spikes = {}
	for i = 1, 7 do
		local angle = (i - 1) * (2 * math.pi / 7) + (math.random() - 0.5) * 0.2
		local h = 4 + math.random() * 2
		local outward = 1.8
		local spike = newPart({
			Material = Enum.Material.Glass, Color = ice,
			Size = Vector3.new(0.6, h, 0.6),
			CFrame = CFrame.new(pos.X + math.cos(angle) * outward,
				groundY - h * 0.5, -- start hidden in ground
				pos.Z + math.sin(angle) * outward)
				* CFrame.Angles(math.rad(8 * math.cos(angle)), angle,
					math.rad(8 * math.sin(angle))),
			Transparency = 0.2, Reflectance = 0.6,
		})
		spike.Parent = workspace
		Debris:AddItem(spike, 2)
		tween(spike, 0.25,
			{ CFrame = spike.CFrame + Vector3.new(0, h * 0.5 + 0.3, 0) },
			Enum.EasingStyle.Back, Enum.EasingDirection.Out
		):Play()
		table.insert(spikes, { part = spike, angle = angle, h = h })
	end

	-- After a beat, shatter: spikes spin & fly outward + go transparent.
	task.delay(0.8, function()
		for _, s in ipairs(spikes) do
			if s.part.Parent then
				local outward = Vector3.new(math.cos(s.angle), 0.4, math.sin(s.angle)) * 16
				tween(s.part, 0.6, {
					CFrame = s.part.CFrame + outward
						+ Vector3.new(0, math.random() * 3, 0),
					Transparency = 1,
				}):Play()
			end
		end
	end)

	-- Frosty mist particles.
	local at = Instance.new("Attachment")
	at.WorldCFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0))
	at.Parent = workspace.Terrain
	Debris:AddItem(at, 1.8)
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = SMOKE_TEX
	mist.Color = ColorSequence.new(Color3.fromRGB(230, 245, 255))
	mist.Size = NumberSequence.new(3, 6)
	mist.Lifetime = NumberRange.new(0.8, 1.4)
	mist.Speed = NumberRange.new(2, 6)
	mist.SpreadAngle = Vector2.new(180, 180)
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.LightEmission = 0.3
	mist.Rate = 0
	mist.Parent = at
	mist:Emit(40)

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = SPARK_TEX
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	sparkle.Size = NumberSequence.new(1.2, 0.1)
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(4, 12)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Rate = 0
	sparkle.Parent = at
	sparkle:Emit(60)

	local light = Instance.new("PointLight")
	light.Color = ice; light.Range = 20; light.Brightness = 4; light.Shadows = false
	light.Parent = at
	tween(light, 1.5, { Brightness = 0 }):Play()
end

-- Lightning storm. Multiple zigzag bolt segments + central plasma orb.
local function playVoltage(victim)
	local pos = getOrigin(victim); if not pos then return end
	local volt = Color3.fromRGB(225, 110, 255)
	local volt2 = Color3.fromRGB(255, 200, 255)

	-- Central plasma orb at body height.
	local orb = newPart({
		Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
		Color = volt, Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(pos), Transparency = 0,
	})
	orb.Parent = workspace
	Debris:AddItem(orb, 1.6)
	tween(orb, 0.3, { Size = Vector3.new(4, 4, 4) },
		Enum.EasingStyle.Back, Enum.EasingDirection.Out):Play()
	task.delay(0.4, function()
		tween(orb, 0.9, { Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1 }):Play()
	end)

	-- 6 zigzag bolts. Each bolt = 5 short segments stitched end-to-end at
	-- random small offsets so the line looks fractured/electric.
	for boltI = 1, 6 do
		local baseAngle = (boltI - 1) * (math.pi / 3)
		local outward = 12
		local endPos = pos + Vector3.new(
			math.cos(baseAngle) * outward,
			(math.random() - 0.4) * 10,
			math.sin(baseAngle) * outward
		)
		local segments = 6
		local prev = pos
		for s = 1, segments do
			local t = s / segments
			local target = pos:Lerp(endPos, t)
				+ Vector3.new(
					(math.random() - 0.5) * 1.5,
					(math.random() - 0.5) * 1.5,
					(math.random() - 0.5) * 1.5
				)
			local mid = (prev + target) * 0.5
			local len = (target - prev).Magnitude
			local seg = newPart({
				Material = Enum.Material.Neon,
				Color = (s % 2 == 0) and volt2 or volt,
				Size = Vector3.new(0.18, 0.18, len),
				CFrame = CFrame.lookAt(mid, target),
				Transparency = 0,
			})
			seg.Parent = workspace
			Debris:AddItem(seg, 0.6)
			tween(seg, 0.5, { Transparency = 1, Size = Vector3.new(0.05, 0.05, len) }):Play()
			prev = target
		end
	end

	-- EMP-like ring expanding at body level.
	local ring = newPart({
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon, Color = volt,
		Size = Vector3.new(0.4, 1, 1),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi * 0.5),
		Transparency = 0.2,
	})
	ring.Parent = workspace
	Debris:AddItem(ring, 1)
	tween(ring, 0.8, { Size = Vector3.new(0.4, 18, 18), Transparency = 1 }):Play()

	-- Sparkle particles + light.
	local at = Instance.new("Attachment")
	at.WorldCFrame = CFrame.new(pos)
	at.Parent = workspace.Terrain
	Debris:AddItem(at, 1.6)
	local p = Instance.new("ParticleEmitter")
	p.Texture = SPARK_TEX
	p.Color = ColorSequence.new(volt2)
	p.Size = NumberSequence.new(1.4, 0.1)
	p.Lifetime = NumberRange.new(0.4, 0.8)
	p.Speed = NumberRange.new(6, 18)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Rotation = NumberRange.new(0, 360)
	p.RotSpeed = NumberRange.new(-360, 360)
	p.LightEmission = 1
	p.Rate = 0
	p.Parent = at
	p:Emit(50)

	local light = Instance.new("PointLight")
	light.Color = volt; light.Range = 22; light.Brightness = 6; light.Shadows = false
	light.Parent = at
	-- Flicker the light over the lifetime to feel electric.
	task.spawn(function()
		for i = 1, 14 do
			if not light.Parent then return end
			light.Brightness = (i % 2 == 0) and 6 or 1.5
			task.wait(0.06)
		end
		if light.Parent then
			tween(light, 0.6, { Brightness = 0 }):Play()
		end
	end)
end

-- Coin shower. Many small gold cylinders spawn at body height and tween
-- along arc-like paths outward, ending in a low ring on the ground.
local function playGoldRush(victim)
	local pos = getOrigin(victim); if not pos then return end
	local groundY = pos.Y - 2.6
	local gold = Color3.fromRGB(255, 215, 70)
	local goldLight = Color3.fromRGB(255, 245, 160)

	-- Bright ground ring.
	local ring = newPart({
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon, Color = gold,
		Size = Vector3.new(0.3, 1, 1),
		CFrame = CFrame.new(pos.X, groundY + 0.05, pos.Z)
			* CFrame.Angles(0, 0, math.pi * 0.5),
		Transparency = 0.1,
	})
	ring.Parent = workspace
	Debris:AddItem(ring, 1.6)
	tween(ring, 1.2, { Size = Vector3.new(0.3, 14, 14), Transparency = 1 }):Play()

	-- 16 gold "coins" (thin cylinders) flying outward in 3D arcs.
	for i = 1, 16 do
		local angle = (i / 16) * math.pi * 2 + math.random() * 0.2
		local outward = 5 + math.random() * 7
		local upward = 3 + math.random() * 4
		local coin = newPart({
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Foil, Color = gold,
			Size = Vector3.new(0.18, 1.0, 1.0),
			CFrame = CFrame.new(pos)
				* CFrame.Angles(math.random() * math.pi, math.random() * math.pi, 0),
			Reflectance = 0.6,
		})
		coin.Parent = workspace
		Debris:AddItem(coin, 1.8)

		local apex = pos + Vector3.new(math.cos(angle) * outward * 0.5,
			upward, math.sin(angle) * outward * 0.5)
		local landing = Vector3.new(pos.X + math.cos(angle) * outward,
			groundY + 0.5, pos.Z + math.sin(angle) * outward)

		-- Two-stage tween: fly up and out (apex), then drop to the ground
		-- with a spin so the coin reads as falling money.
		tween(coin, 0.4, {
			CFrame = CFrame.new(apex)
				* CFrame.Angles(math.random() * math.pi * 2,
					math.random() * math.pi * 2, 0),
		}):Play()
		task.delay(0.4, function()
			if coin.Parent then
				tween(coin, 0.7, {
					CFrame = CFrame.new(landing) * CFrame.Angles(math.pi * 0.5, 0, 0),
					Transparency = 0.3,
				}, Enum.EasingStyle.Quad, Enum.EasingDirection.In):Play()
			end
		end)
		task.delay(1.3, function()
			if coin.Parent then tween(coin, 0.4, { Transparency = 1 }):Play() end
		end)
	end

	-- Gold dust particles.
	local at = Instance.new("Attachment")
	at.WorldCFrame = CFrame.new(pos)
	at.Parent = workspace.Terrain
	Debris:AddItem(at, 1.8)
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SPARK_TEX
	dust.Color = ColorSequence.new(goldLight)
	dust.Size = NumberSequence.new(1.6, 0.1)
	dust.Lifetime = NumberRange.new(0.6, 1.0)
	dust.Speed = NumberRange.new(4, 14)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-360, 360)
	dust.LightEmission = 1
	dust.Rate = 0
	dust.Parent = at
	dust:Emit(70)

	local light = Instance.new("PointLight")
	light.Color = goldLight; light.Range = 22; light.Brightness = 5; light.Shadows = false
	light.Parent = at
	tween(light, 1.5, { Brightness = 0 }):Play()
end

local PLAYERS = {
	Shockwave = playShockwave,
	Inferno = playInferno,
	Frostbite = playFrostbite,
	Voltage = playVoltage,
	GoldRush = playGoldRush,
}

-- Wrapped in pcall so a single broken effect can't throw inside the
-- death pipeline and block ELO updates / coin awards for the match.
function KillEffectsCatalog.apply(victimChar, effectName)
	if not victimChar then return end
	local fn = PLAYERS[effectName]
	if not fn then return end
	pcall(fn, victimChar)
end

function KillEffectsCatalog.exists(name)
	return KillEffectsCatalog.Effects[name] ~= nil
end

function KillEffectsCatalog.priceOf(name)
	local def = KillEffectsCatalog.Effects[name]
	return def and def.robuxPrice or 0, def and def.coinPrice or 0
end

return KillEffectsCatalog
