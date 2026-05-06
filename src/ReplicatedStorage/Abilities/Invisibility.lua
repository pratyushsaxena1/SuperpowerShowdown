local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VFX = require(ReplicatedStorage.SharedModules.VFX)

local Invisibility = {}

Invisibility.cooldown = 5
Invisibility.meleeDamage = 10
Invisibility.speedMultiplier = 1.1
Invisibility.duration = 3

local SKIN_ATTACHMENT_NAMES = {
	SkinParticles = true,
	SkinAura = true,
	SkinCrown = true,
	SkinSecondary = true,
	SkinFootAura = true,
}

-- Toggle the skin's Highlight, PointLight, particles, and trail. Without
-- this, an invisible player wearing a skin still glows + leaves a trail.
local function setSkinVisible(character, visible)
	local highlight = character:FindFirstChild("SkinAccents_Highlight")
	if highlight and highlight:IsA("Highlight") then
		highlight.Enabled = visible
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local bin = hrp and hrp:FindFirstChild("SkinAccents")
	if bin then
		for _, d in ipairs(bin:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Light") then
				d.Enabled = visible
			end
		end
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Attachment") and SKIN_ATTACHMENT_NAMES[d.Name] then
			for _, child in ipairs(d:GetChildren()) do
				if child:IsA("ParticleEmitter") then
					child.Enabled = visible
				end
			end
		end
	end
end

-- Hides every visible part on the character. We snapshot each part's
-- baseline transparency on the first hide so reveal can restore it; this
-- matters for skin decoration parts (aura sphere, ground ring, etc.) that
-- have non-zero baseline transparency. Without the snapshot, reveal would
-- set everything to 0 and the aura/ring would become fully opaque.
local function setTransparency(character, hide)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			if hide then
				if part:GetAttribute("InvisOrigTransparency") == nil then
					part:SetAttribute("InvisOrigTransparency", part.Transparency)
				end
				part.LocalTransparencyModifier = 1
				part.Transparency = 1
			else
				local orig = part:GetAttribute("InvisOrigTransparency") or 0
				part.LocalTransparencyModifier = orig
				part.Transparency = orig
				part:SetAttribute("InvisOrigTransparency", nil)
			end
		elseif part:IsA("Decal") then
			if hide then
				if part:GetAttribute("InvisOrigTransparency") == nil then
					part:SetAttribute("InvisOrigTransparency", part.Transparency)
				end
				part.Transparency = 1
			else
				local orig = part:GetAttribute("InvisOrigTransparency") or 0
				part.Transparency = orig
				part:SetAttribute("InvisOrigTransparency", nil)
			end
		end
	end
end

local function reveal(character)
	setTransparency(character, false)
	setSkinVisible(character, true)
	character:SetAttribute("IsInvisible", false)
end

function Invisibility.onEquip() end
function Invisibility.onUnequip(character)
	if character then
		reveal(character)
	end
end

function Invisibility.onActivate(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then VFX.sphereBurst(root.Position, Color3.fromRGB(180, 180, 200), 5, 0.3) end
	setTransparency(character, true)
	setSkinVisible(character, false)
	character:SetAttribute("IsInvisible", true)
	task.delay(Invisibility.duration, function()
		if character and character.Parent then
			if character:GetAttribute("IsInvisible") then
				reveal(character)
			end
		end
	end)
end

-- Called when the invisible character gets HIT (takes damage).
function Invisibility.onHit(character)
	if character and character:GetAttribute("IsInvisible") then
		reveal(character)
	end
end

-- Called when the invisible character ATTACKS (punches/fires) - stealth breaks
-- the moment you swing. Same reveal as onHit.
function Invisibility.onAttack(character)
	if character and character:GetAttribute("IsInvisible") then
		reveal(character)
	end
end

return Invisibility
