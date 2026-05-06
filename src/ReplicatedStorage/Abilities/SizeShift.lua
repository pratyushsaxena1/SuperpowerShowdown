local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VFX = require(ReplicatedStorage.SharedModules.VFX)

local SizeShift = {}

SizeShift.cooldown = 0.8
SizeShift.meleeDamage = 8
SizeShift.speedMultiplier = 1.0

-- Cycle order: Normal -> Big -> Small -> Normal
local STATES = {
	{ name = "Normal", scale = 1.0,  speed = 16, dmg = 1.0, taken = 1.0, color = Color3.fromRGB(220, 220, 220) },
	{ name = "Big",    scale = 1.6,  speed = 12, dmg = 1.5, taken = 0.85, color = Color3.fromRGB(255, 160, 120) },
	{ name = "Small",  scale = 0.55, speed = 24, dmg = 0.75, taken = 1.25, color = Color3.fromRGB(140, 220, 255) },
}

local SCALE_NAMES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }

local function applyScale(character, scale)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	for _, name in ipairs(SCALE_NAMES) do
		local nv = hum:FindFirstChild(name)
		if nv and nv:IsA("NumberValue") then nv.Value = scale end
	end
end

local function applyState(character, stateIdx)
	local s = STATES[stateIdx]
	if not s then return end
	applyScale(character, s.scale)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = s.speed end
	character:SetAttribute("DamageMultiplier", s.dmg)
	character:SetAttribute("IncomingDamageMultiplier", s.taken)
	character:SetAttribute("SizeState", stateIdx)
end

function SizeShift.onEquip(character)
	character:SetAttribute("SizeState", 1)
end

function SizeShift.onUnequip(character)
	if not character then return end
	applyScale(character, 1)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = 16 end
	character:SetAttribute("DamageMultiplier", 1)
	character:SetAttribute("IncomingDamageMultiplier", 1)
	character:SetAttribute("SizeState", 1)
end

function SizeShift.onActivate(character)
	local idx = character:GetAttribute("SizeState") or 1
	idx = (idx % #STATES) + 1
	local s = STATES[idx]
	applyState(character, idx)

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		VFX.sphereBurst(root.Position, s.color, 6 * s.scale, 0.35)
		VFX.ring(root.Position, s.color, 7 * s.scale, 0.4)
	end
end

return SizeShift
