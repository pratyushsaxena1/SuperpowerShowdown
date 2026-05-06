local Shadow = {}
Shadow.Name = "Shadow"
Shadow.DisplayName = "Shadowstrike"
Shadow.Description = "Dash 30 studs, briefly invulnerable, 25 dmg to anyone hit."
Shadow.Cooldown = 5
Shadow.Color = Color3.fromRGB(80, 60, 130)
Shadow.PunchDamageMultiplier = 1.2

function Shadow.onMatchStart(_state) end

function Shadow.activate(state)
	state.requestDash(state.player, 30, 25, {
		kind = "shadowDash",
		invuln = 0.5,
		sweepRadius = 6,
	})
end

function Shadow.cleanup(_state) end

return Shadow
