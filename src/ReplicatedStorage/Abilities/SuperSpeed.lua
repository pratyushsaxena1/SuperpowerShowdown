local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VFX = require(ReplicatedStorage.SharedModules.VFX)

local SuperSpeed = {}

SuperSpeed.cooldown = 3.5
SuperSpeed.meleeDamage = 6
SuperSpeed.speedMultiplier = 1.6
SuperSpeed.boostDuration = 3
SuperSpeed.boostMultiplier = 2.6

-- Re-apply the standard jump strength every time we touch WalkSpeed. At
-- very high WalkSpeed values, Roblox's character controller sometimes
-- leaves the Humanoid in a Freefall state long enough to swallow Space
-- presses; locking JumpPower to 50 alongside any speed change keeps
-- jumping responsive while sprinting.
local function setSpeed(hum, walk)
	if not hum then return end
	hum.JumpPower = 50
	hum.WalkSpeed = walk
end

function SuperSpeed.onEquip(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	setSpeed(hum, 16 * SuperSpeed.speedMultiplier)
end

function SuperSpeed.onUnequip(character)
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	setSpeed(hum, 16)
end

function SuperSpeed.onActivate(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end
	local baseline = 16 * SuperSpeed.speedMultiplier
	setSpeed(hum, 16 * SuperSpeed.boostMultiplier)

	local stop = false
	task.spawn(function()
		while not stop do
			VFX.sparkle(root.Position, Color3.fromRGB(255, 220, 120), 3, 1.2, 0.4)
			task.wait(0.1)
		end
	end)
	task.delay(SuperSpeed.boostDuration, function()
		stop = true
		if hum and hum.Parent then setSpeed(hum, baseline) end
	end)
end

return SuperSpeed
