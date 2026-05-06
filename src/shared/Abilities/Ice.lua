local Ice = {}
Ice.Name = "Ice"
Ice.DisplayName = "Cryomancer"
Ice.Description = "Freeze your opponent in place for 1.5s + 15 dmg."
Ice.Cooldown = 7
Ice.Color = Color3.fromRGB(140, 220, 255)
Ice.PunchDamageMultiplier = 1.0

function Ice.onMatchStart(_state) end

function Ice.activate(state)
	local char = state.character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local origin = root.Position + Vector3.new(0, 1.5, 0) + root.CFrame.LookVector * 3
	local dir = root.CFrame.LookVector

	state.requestProjectile(state.player, origin, dir, {
		kind = "iceShard",
		damage = 15,
		speed = 110,
		range = 100,
		hitRadius = 5,
		onHit = function(target)
			state.requestFreeze(target, 1.5)
		end,
	})
end

function Ice.cleanup(_state) end

return Ice
