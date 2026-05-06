local Telekinesis = {}
Telekinesis.Name = "Telekinesis"
Telekinesis.DisplayName = "Telekinetic"
Telekinesis.Description = "Lift your opponent for 1.2s, then slam them down for 25 dmg."
Telekinesis.Cooldown = 7
Telekinesis.Color = Color3.fromRGB(170, 100, 220)
Telekinesis.PunchDamageMultiplier = 1.0

function Telekinesis.onMatchStart(_state) end

function Telekinesis.activate(state)
	local opp = state.getOpponent(state.player)
	if not opp then return end
	state.requestLift(state.player, opp, 1.2, 25)
end

function Telekinesis.cleanup(_state) end

return Telekinesis
