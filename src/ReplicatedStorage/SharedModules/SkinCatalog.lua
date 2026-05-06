-- Shared skin definitions: metadata (for UI) and visual application.
-- Each skin layers: subtle body recolor + non-glowing material so the
-- character's silhouette stays readable, a Highlight outline for "champion"
-- presence, a PointLight for ambient color, signature particle effects
-- (crown, hand auras, foot bursts), and a motion trail.
--
-- The key visual rule: the BODY shouldn't glow as a uniform color — that
-- looks like a bright blob. The character should still read as a Roblox
-- character with cool effects layered on top.

local TweenService = game:GetService("TweenService")

local SkinCatalog = {}

SkinCatalog.DEFAULT_COLOR = Color3.fromRGB(248, 217, 109)
SkinCatalog.Order = { "Fire", "Ice", "Neon", "Gold" }

local FIRE_TEX    = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEX   = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"

-- Skin design philosophy:
--   * Body color is muted/themed, not a saturated glow blob — the
--     character's silhouette stays readable as a Roblox character.
--   * Highlight is OUTLINE-ONLY (FillTransparency = 1) so the body
--     shape reads instead of being swallowed by a fill color.
--   * Each skin has ONE signature element (crown OR foot bursts OR
--     halo), not all of them at once.
--   * Trail + PointLight provide the "vibe" without overpowering.
SkinCatalog.Skins = {
	Fire = {
		name = "Fire",
		price = 25,
		coinPrice = 5000,
		description = "Burning warrior. Smoldering body with a flame crown and ember footsteps.",
		accentColor = Color3.fromRGB(255, 130, 60),
		bodyColor = Color3.fromRGB(120, 36, 20),
		material = Enum.Material.SmoothPlastic,
		reflectance = 0,
		lightColor = Color3.fromRGB(255, 140, 60),
		lightBrightness = 2.4,
		lightRange = 14,
		highlightOutline = Color3.fromRGB(255, 180, 80),
		highlightFillTransparency = 1, -- outline only
		highlightFill = Color3.fromRGB(255, 100, 40),
		trailColorA = Color3.fromRGB(255, 220, 100),
		trailColorB = Color3.fromRGB(180, 40, 10),
		trailLifetime = 0.55,
		crownTexture = FIRE_TEX,
		crownRate = 60,
		crownColor = Color3.fromRGB(255, 170, 50),
		crownSize = 2.4,
		footParticleRate = 18,
		particleColor = Color3.fromRGB(255, 160, 60),
		particleTexture = FIRE_TEX,
	},
	Ice = {
		name = "Ice",
		price = 25,
		coinPrice = 5000,
		description = "Glacial sovereign. Frosted crystalline body with a glittering frost halo.",
		accentColor = Color3.fromRGB(150, 230, 255),
		bodyColor = Color3.fromRGB(180, 220, 240),
		material = Enum.Material.Glass,
		reflectance = 0.4,
		lightColor = Color3.fromRGB(180, 230, 255),
		lightBrightness = 2.0,
		lightRange = 14,
		highlightOutline = Color3.fromRGB(230, 245, 255),
		highlightFillTransparency = 1,
		highlightFill = Color3.fromRGB(180, 230, 255),
		trailColorA = Color3.fromRGB(255, 255, 255),
		trailColorB = Color3.fromRGB(140, 210, 255),
		trailLifetime = 0.65,
		crownTexture = SPARKLE_TEX,
		crownRate = 50,
		crownColor = Color3.fromRGB(220, 240, 255),
		crownSize = 2.0,
		-- No body / hand / foot emitters: Ice should feel quiet and clean.
	},
	Neon = {
		name = "Neon",
		price = 25,
		coinPrice = 5000,
		description = "Holographic strike-suit. Dark cyber armor outlined in pulsing magenta light.",
		accentColor = Color3.fromRGB(240, 100, 255),
		bodyColor = Color3.fromRGB(34, 18, 50),
		material = Enum.Material.SmoothPlastic,
		reflectance = 0,
		lightColor = Color3.fromRGB(240, 100, 255),
		lightBrightness = 3.0,
		lightRange = 14,
		highlightOutline = Color3.fromRGB(245, 130, 255),
		highlightFillTransparency = 1,
		highlightFill = Color3.fromRGB(220, 80, 255),
		trailColorA = Color3.fromRGB(255, 180, 255),
		trailColorB = Color3.fromRGB(80, 30, 200),
		trailLifetime = 0.7,
		crownTexture = SPARKLE_TEX,
		crownRate = 70,
		crownColor = Color3.fromRGB(240, 120, 255),
		crownSize = 2.2,
		pulseLight = true,
	},
	Gold = {
		name = "Gold",
		price = 25,
		coinPrice = 5000,
		description = "Champion of legends. Polished gold armor with a divine spinning halo.",
		accentColor = Color3.fromRGB(255, 220, 100),
		bodyColor = Color3.fromRGB(230, 180, 50),
		material = Enum.Material.Foil,
		reflectance = 0.85,
		lightColor = Color3.fromRGB(255, 220, 120),
		lightBrightness = 2.6,
		lightRange = 14,
		highlightOutline = Color3.fromRGB(255, 240, 180),
		highlightFillTransparency = 1,
		highlightFill = Color3.fromRGB(255, 210, 60),
		trailColorA = Color3.fromRGB(255, 250, 180),
		trailColorB = Color3.fromRGB(220, 150, 0),
		trailLifetime = 0.55,
		crownTexture = SPARKLE_TEX,
		crownRate = 60,
		crownColor = Color3.fromRGB(255, 230, 120),
		crownSize = 2.4,
		halo = true,
	},
}

local BODY_PART_NAMES = {
	Head = true, Torso = true,
	["Left Arm"] = true, ["Right Arm"] = true,
	["Left Leg"] = true, ["Right Leg"] = true,
	UpperTorso = true, LowerTorso = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

local AURA_PARTS = {
	"RightHand", "LeftHand",
	"Right Arm", "Left Arm",
}

local FOOT_PARTS = {
	"RightFoot", "LeftFoot",
	"Right Leg", "Left Leg",
}

local function removeAccents(character)
	local hl = character:FindFirstChild("SkinAccents_Highlight")
	if hl then hl:Destroy() end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local bin = hrp and hrp:FindFirstChild("SkinAccents")
	if bin then bin:Destroy() end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Attachment")
			and (d.Name == "SkinParticles" or d.Name == "SkinAura"
				or d.Name == "SkinCrown" or d.Name == "SkinTrailTop"
				or d.Name == "SkinTrailBot" or d.Name == "SkinFootAura"
				or d.Name == "SkinSecondary") then
			d:Destroy()
		end
	end
end

local function clearSkin(character)
	removeAccents(character)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and BODY_PART_NAMES[d.Name] then
			d.Material = Enum.Material.Plastic
			d.Color = SkinCatalog.DEFAULT_COLOR
			d.Reflectance = 0
			d.Transparency = d.Name == "HumanoidRootPart" and 1 or 0
		end
	end
	local bc = character:FindFirstChildOfClass("BodyColors")
	if bc then
		local defaultCol = BrickColor.new("Bright yellow")
		bc.HeadColor = defaultCol; bc.TorsoColor = defaultCol
		bc.LeftArmColor = defaultCol; bc.RightArmColor = defaultCol
		bc.LeftLegColor = defaultCol; bc.RightLegColor = defaultCol
	end
end

local function newEmitter(def, rate, lifeMin, lifeMax, sizeStart, sizeEnd, spread, color, texture)
	local p = Instance.new("ParticleEmitter")
	p.Texture = texture or def.particleTexture or SPARKLE_TEX
	p.Color = ColorSequence.new(color or def.particleColor)
	p.Rate = rate
	p.Lifetime = NumberRange.new(lifeMin, lifeMax)
	p.Size = NumberSequence.new(sizeStart, sizeEnd)
	p.Speed = NumberRange.new(0.5, 2)
	p.SpreadAngle = Vector2.new(spread, spread)
	p.Rotation = NumberRange.new(0, 360)
	p.RotSpeed = NumberRange.new(-180, 180)
	p.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	p.LightEmission = 0.7
	p.LightInfluence = 0
	return p
end

function SkinCatalog.apply(character, skinName)
	if not character then return end
	clearSkin(character)
	if not skinName or skinName == "" or skinName == "None" then return end
	local def = SkinCatalog.Skins[skinName]
	if not def then return end

	-- Body recolor + material + reflectance.
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and BODY_PART_NAMES[d.Name] then
			d.Material = def.material
			d.Color = def.bodyColor
			d.Reflectance = def.reflectance or 0
		end
	end

	-- BodyColors override: Roblox's Animate script reapplies the player's
	-- avatar palette each frame without this.
	local bc = character:FindFirstChildOfClass("BodyColors")
	if bc then
		local bcCol = BrickColor.new(def.bodyColor)
		bc.HeadColor = bcCol; bc.TorsoColor = bcCol
		bc.LeftArmColor = bcCol; bc.RightArmColor = bcCol
		bc.LeftLegColor = bcCol; bc.RightLegColor = bcCol
	end

	-- Highlight outline: the main "champion" presence — outline-only with
	-- nearly transparent fill, so the body silhouette reads instead of
	-- becoming a glowing blob.
	local highlight = Instance.new("Highlight")
	highlight.Name = "SkinAccents_Highlight"
	highlight.FillColor = def.highlightFill or def.bodyColor
	highlight.OutlineColor = def.highlightOutline or def.accentColor
	highlight.FillTransparency = def.highlightFillTransparency or 0.85
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = character

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local bin = Instance.new("Folder")
	bin.Name = "SkinAccents"
	bin.Parent = hrp

	-- PointLight: tints nearby surfaces with the skin color.
	local light = Instance.new("PointLight")
	light.Color = def.lightColor
	light.Range = def.lightRange or 12
	light.Brightness = def.lightBrightness or 2.5
	light.Shadows = false
	light.Parent = bin

	if def.pulseLight then
		task.spawn(function()
			while light and light.Parent do
				local target = (def.lightBrightness or 3) * 1.5
				local low = (def.lightBrightness or 3) * 0.7
				local goal = TweenService:Create(light,
					TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Brightness = target })
				goal:Play()
				goal.Completed:Wait()
				if not (light and light.Parent) then break end
				local back = TweenService:Create(light,
					TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Brightness = low })
				back:Play()
				back.Completed:Wait()
			end
		end)
	end

	-- Optional body emitter. Most skins skip this — uniform body particle
	-- smoke flattens the silhouette into a "blob". Set particleRate > 0
	-- to opt in.
	if def.particleRate and def.particleRate > 0 then
		local mainAttach = Instance.new("Attachment")
		mainAttach.Name = "SkinParticles"
		mainAttach.Position = Vector3.new(0, 0, 0)
		mainAttach.Parent = hrp
		local mainEmitter = newEmitter(def, def.particleRate, 0.4, 0.9, 0.6, 0.1, 80)
		mainEmitter.Parent = mainAttach
	end

	-- Motion trail: short, only appears while moving.
	local trailTop = Instance.new("Attachment")
	trailTop.Name = "SkinTrailTop"
	trailTop.Position = Vector3.new(0, 1.2, 0)
	trailTop.Parent = hrp
	local trailBot = Instance.new("Attachment")
	trailBot.Name = "SkinTrailBot"
	trailBot.Position = Vector3.new(0, -1.6, 0)
	trailBot.Parent = hrp

	local trail = Instance.new("Trail")
	trail.Attachment0 = trailTop
	trail.Attachment1 = trailBot
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, def.trailColorA or def.accentColor),
		ColorSequenceKeypoint.new(1, def.trailColorB or def.bodyColor),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = def.trailLifetime or 0.6
	trail.MinLength = 0.5
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Parent = bin

	-- Signature crown above head: the per-skin identity element.
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local crownAttach = Instance.new("Attachment")
		crownAttach.Name = "SkinCrown"
		crownAttach.Position = Vector3.new(0, 1.3, 0)
		crownAttach.Parent = head
		local crown = Instance.new("ParticleEmitter")
		crown.Texture = def.crownTexture or def.particleTexture or SPARKLE_TEX
		crown.Color = ColorSequence.new(def.crownColor or def.accentColor)
		crown.Rate = def.crownRate or 40
		crown.Lifetime = NumberRange.new(0.3, 0.7)
		crown.Size = NumberSequence.new(def.crownSize or 2, 0.1)
		crown.Speed = NumberRange.new(0.3, 1)
		crown.SpreadAngle = Vector2.new(40, 40)
		crown.Rotation = NumberRange.new(0, 360)
		crown.RotSpeed = NumberRange.new(-200, 200)
		crown.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		crown.LightEmission = 1
		crown.LightInfluence = 0
		crown.Parent = crownAttach

		-- Gold halo: spinning ring of particles directly above head.
		if def.halo then
			local haloAttach = Instance.new("Attachment")
			haloAttach.Name = "SkinCrown"
			haloAttach.Position = Vector3.new(0, 2.2, 0)
			haloAttach.Parent = head
			local halo = Instance.new("ParticleEmitter")
			halo.Texture = SPARKLE_TEX
			halo.Color = ColorSequence.new(def.crownColor or def.accentColor)
			halo.Rate = 150
			halo.Lifetime = NumberRange.new(0.5, 0.8)
			halo.Size = NumberSequence.new(1.2, 0.3)
			halo.Speed = NumberRange.new(0, 0)
			halo.SpreadAngle = Vector2.new(0, 0)
			halo.Rotation = NumberRange.new(0, 360)
			halo.RotSpeed = NumberRange.new(360, 720)
			halo.Transparency = NumberSequence.new(0.2, 1)
			halo.LightEmission = 1
			halo.Parent = haloAttach
		end
	end

	-- Optional hand auras. Set limbParticleRate > 0 to opt in.
	if def.limbParticleRate and def.limbParticleRate > 0 then
		for _, partName in ipairs(AURA_PARTS) do
			local part = character:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				local attach = Instance.new("Attachment")
				attach.Name = "SkinAura"
				attach.Parent = part
				local e = newEmitter(def, def.limbParticleRate,
					0.25, 0.6, 0.7, 0.1, 100)
				e.Parent = attach
			end
		end
	end

	-- Optional foot bursts. Set footParticleRate > 0 to opt in.
	if def.footParticleRate and def.footParticleRate > 0 then
		for _, partName in ipairs(FOOT_PARTS) do
			local part = character:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				local attach = Instance.new("Attachment")
				attach.Name = "SkinFootAura"
				attach.Position = Vector3.new(0, -0.6, 0)
				attach.Parent = part
				local e = newEmitter(def, def.footParticleRate,
					0.3, 0.7, 0.9, 0.1, 70)
				e.Speed = NumberRange.new(1, 3)
				e.Acceleration = Vector3.new(0, 3, 0)
				e.Parent = attach
			end
		end
	end
end

-- Static preview application for ViewportFrame previews. ViewportFrames
-- don't render particles/trails/lights, so we lean on body color, material,
-- highlight, and a tinted backdrop to communicate the skin.
function SkinCatalog.applyPreview(model, skinName)
	if not model then return end
	local def = SkinCatalog.Skins[skinName]
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and BODY_PART_NAMES[d.Name] then
			if def then
				d.Material = def.material
				d.Color = def.bodyColor
				d.Reflectance = def.reflectance or 0
			else
				d.Material = Enum.Material.Plastic
				d.Color = SkinCatalog.DEFAULT_COLOR
				d.Reflectance = 0
			end
		end
	end
	local bc = model:FindFirstChildOfClass("BodyColors")
	if bc and def then
		local bcCol = BrickColor.new(def.bodyColor)
		bc.HeadColor = bcCol; bc.TorsoColor = bcCol
		bc.LeftArmColor = bcCol; bc.RightArmColor = bcCol
		bc.LeftLegColor = bcCol; bc.RightLegColor = bcCol
	end
	local existing = model:FindFirstChild("PreviewHighlight")
	if existing then existing:Destroy() end
	if def then
		local hl = Instance.new("Highlight")
		hl.Name = "PreviewHighlight"
		hl.FillColor = def.highlightFill or def.bodyColor
		hl.OutlineColor = def.highlightOutline or def.accentColor
		hl.FillTransparency = def.highlightFillTransparency or 0.85
		hl.OutlineTransparency = 0
		hl.Adornee = model
		hl.Parent = model
	end
end

function SkinCatalog.priceOf(skinName)
	local def = SkinCatalog.Skins[skinName]
	return def and def.price or 0
end

function SkinCatalog.coinPriceOf(skinName)
	local def = SkinCatalog.Skins[skinName]
	return def and def.coinPrice or 0
end

function SkinCatalog.exists(skinName)
	return SkinCatalog.Skins[skinName] ~= nil
end

return SkinCatalog
