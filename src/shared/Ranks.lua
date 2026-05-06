local Ranks = {}

-- Ordered low → high. Last tier has no upper bound.
Ranks.Tiers = {
	{ name = "Bronze",      min = 0,    color = Color3.fromRGB(180, 110,  60), accent = Color3.fromRGB(220, 150,  90) },
	{ name = "Silver",      min = 900,  color = Color3.fromRGB(190, 200, 215), accent = Color3.fromRGB(230, 240, 250) },
	{ name = "Gold",        min = 1050, color = Color3.fromRGB(255, 205,  80), accent = Color3.fromRGB(255, 235, 140) },
	{ name = "Platinum",    min = 1200, color = Color3.fromRGB(110, 230, 220), accent = Color3.fromRGB(170, 250, 240) },
	{ name = "Diamond",     min = 1400, color = Color3.fromRGB(120, 200, 255), accent = Color3.fromRGB(180, 230, 255) },
	{ name = "Master",      min = 1650, color = Color3.fromRGB(200, 120, 255), accent = Color3.fromRGB(230, 180, 255) },
	{ name = "Grandmaster", min = 1900, color = Color3.fromRGB(255, 110, 130), accent = Color3.fromRGB(255, 200, 210) },
}

function Ranks.fromElo(elo)
	local t = Ranks.Tiers[1]
	for i = 1, #Ranks.Tiers do
		if elo >= Ranks.Tiers[i].min then t = Ranks.Tiers[i] end
	end
	return t
end

-- Progress to next tier (0 → 1). Returns 1 for the top tier.
function Ranks.progress(elo)
	local current = Ranks.fromElo(elo)
	local idx = nil
	for i, tier in ipairs(Ranks.Tiers) do
		if tier.name == current.name then idx = i break end
	end
	if not idx or idx == #Ranks.Tiers then return 1 end
	local next_ = Ranks.Tiers[idx + 1]
	local span = next_.min - current.min
	if span <= 0 then return 1 end
	return math.clamp((elo - current.min) / span, 0, 1)
end

function Ranks.label(elo)
	local t = Ranks.fromElo(elo)
	return t.name
end

return Ranks
