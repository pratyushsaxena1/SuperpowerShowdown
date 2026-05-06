local Lightning = {}
Lightning.Name = "Lightning"
Lightning.DisplayName = "Stormcaller"
Lightning.Description = "Snap an instant chain bolt to your opponent — 30 dmg, 50-stud range."
Lightning.Cooldown = 4
Lightning.Color = Color3.fromRGB(255, 240, 120)
Lightning.PunchDamageMultiplier = 1.0

function Lightning.onMatchStart(_state) end

function Lightning.activate(state)
	state.requestLightning(state.player, 30, 50)
end

function Lightning.cleanup(_state) end

return Lightning
