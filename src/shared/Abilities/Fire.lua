local Fire = {}
Fire.Name = "Fire"
Fire.DisplayName = "Pyromancer"
Fire.Description = "Hurl a fireball — 25 dmg + burn (5 dmg/s for 3s)."
Fire.Cooldown = 4
Fire.Color = Color3.fromRGB(255, 130, 60)
Fire.PunchDamageMultiplier = 1.0

function Fire.onMatchStart(_state) end

function Fire.activate(state)
	local char = state.character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local origin = root.Position + Vector3.new(0, 1.5, 0) + root.CFrame.LookVector * 3
	local dir = root.CFrame.LookVector

	state.requestProjectile(state.player, origin, dir, {
		kind = "fireball",
		damage = 25,
		speed = 90,
		range = 110,
		hitRadius = 5,
		onHit = function(target)
			-- Burn DOT on hit.
			state.requestDOT(target, state.player, 5, 3, 1.0)
		end,
	})
end

function Fire.cleanup(_state) end

return Fire
