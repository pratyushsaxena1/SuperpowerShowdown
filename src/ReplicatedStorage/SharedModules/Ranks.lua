-- Tier ladder displayed over heads, in the lobby HUD, and on result banners.
-- Tied to Elo so climbing the ladder feels like climbing the rank ladder.
-- Tiers are intentionally tight near the bottom (Bronze→Silver→Gold are
-- close together so new players see progress quickly) and stretch out at
-- the top (Master/Grandmaster are real grinds for prestige).
--
-- Elo defaults to 0 in this game (see GameConfig.DefaultElo), so the
-- thresholds start at 0 too.

local Ranks = {}

Ranks.Tiers = {
	{ name = "Bronze",      min = 0,    color = Color3.fromRGB(180, 110,  60), accent = Color3.fromRGB(220, 150,  90) },
	{ name = "Silver",      min = 80,   color = Color3.fromRGB(190, 200, 215), accent = Color3.fromRGB(230, 240, 250) },
	{ name = "Gold",        min = 200,  color = Color3.fromRGB(255, 205,  80), accent = Color3.fromRGB(255, 235, 140) },
	{ name = "Platinum",    min = 360,  color = Color3.fromRGB(110, 230, 220), accent = Color3.fromRGB(170, 250, 240) },
	{ name = "Diamond",     min = 560,  color = Color3.fromRGB(120, 200, 255), accent = Color3.fromRGB(180, 230, 255) },
	{ name = "Master",      min = 800,  color = Color3.fromRGB(200, 120, 255), accent = Color3.fromRGB(230, 180, 255) },
	{ name = "Grandmaster", min = 1100, color = Color3.fromRGB(255, 110, 130), accent = Color3.fromRGB(255, 200, 210) },
}

function Ranks.fromElo(elo)
	elo = elo or 0
	local t = Ranks.Tiers[1]
	for i = 1, #Ranks.Tiers do
		if elo >= Ranks.Tiers[i].min then t = Ranks.Tiers[i] end
	end
	return t
end

function Ranks.label(elo)
	return Ranks.fromElo(elo).name
end

-- Returns (progress 0→1, currentTier, nextTier-or-nil). Top tier returns 1.
function Ranks.progress(elo)
	elo = elo or 0
	local current = Ranks.fromElo(elo)
	local idx
	for i, tier in ipairs(Ranks.Tiers) do
		if tier == current then idx = i break end
	end
	if not idx or idx == #Ranks.Tiers then return 1, current, nil end
	local next_ = Ranks.Tiers[idx + 1]
	local span = next_.min - current.min
	if span <= 0 then return 1, current, next_ end
	return math.clamp((elo - current.min) / span, 0, 1), current, next_
end

return Ranks
