local SuperSpeed = {}
SuperSpeed.Name = "SuperSpeed"
SuperSpeed.DisplayName = "Super Speed"
SuperSpeed.Description = "Always move 2x faster. Press E for a 2-second sprint burst."
SuperSpeed.Cooldown = 6
SuperSpeed.Color = Color3.fromRGB(255, 230, 100)
SuperSpeed.PunchDamageMultiplier = 1.0

local BASE_BOOST = 32

function SuperSpeed.onMatchStart(state)
	local char = state.character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = BASE_BOOST end
end

function SuperSpeed.activate(state)
	local char = state.character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	hum.WalkSpeed = 70
	task.delay(2, function()
		if hum and hum.Parent then hum.WalkSpeed = BASE_BOOST end
	end)
end

function SuperSpeed.cleanup(state)
	local char = state.character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = 16 end
end

return SuperSpeed
