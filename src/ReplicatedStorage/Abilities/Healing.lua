local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VFX = require(ReplicatedStorage.SharedModules.VFX)

local Healing = {}

Healing.cooldown = 7
Healing.meleeDamage = 6
Healing.speedMultiplier = 1.0
Healing.amount = 35

function Healing.onEquip() end
function Healing.onUnequip() end

function Healing.onActivate(character, opponent, ctx)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		VFX.ring(root.Position, Color3.fromRGB(120, 255, 180), 10, 0.6)
		VFX.sparkle(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(120, 255, 180), 12, 3, 0.7)
	end
	if ctx and ctx.healSelf then
		ctx.healSelf(Healing.amount)
	end
end

return Healing
