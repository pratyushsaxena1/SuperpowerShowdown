local SuperStrength = {}
SuperStrength.Name = "SuperStrength"
SuperStrength.DisplayName = "Super Strength"
SuperStrength.Description = "Punches deal 3x damage. Press E for a ground slam shockwave."
SuperStrength.Cooldown = 6
SuperStrength.Color = Color3.fromRGB(255, 120, 80)
SuperStrength.PunchDamageMultiplier = 3.0

function SuperStrength.onMatchStart(_state) end

function SuperStrength.activate(state)
	local char = state.character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	state.requestSlam(state.player, root.Position, 16, 28)
end

function SuperStrength.cleanup(_state) end

return SuperStrength
