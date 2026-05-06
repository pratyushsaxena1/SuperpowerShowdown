local EloCalc = {}

-- Standard Elo formula (K-factor 32). Winning against a higher-rated
-- opponent gains more than against a lower-rated one; the loser drops by
-- the same amount. Zero-sum on the raw deltas (the floor at MinElo in
-- EloDataService is the only thing that breaks zero-sum, and only when a
-- losing player is already at the minimum).
local K = 32

local function expectedScore(ratingA, ratingB)
	return 1 / (1 + 10 ^ ((ratingB - ratingA) / 400))
end

local function roundHalfAwayFromZero(x)
	if x >= 0 then return math.floor(x + 0.5) end
	return -math.floor(-x + 0.5)
end

-- Returns (winnerDelta, loserDelta). Always: winnerDelta = -loserDelta.
function EloCalc.compute(winnerElo, loserElo)
	local exp = expectedScore(winnerElo, loserElo)
	local delta = roundHalfAwayFromZero(K * (1 - exp))
	if delta < 1 then delta = 1 end
	return delta, -delta
end

function EloCalc.applyResult(eloA, eloB, result)
	if result == "draw" then
		-- Draw delta: smaller correction toward the expected outcome.
		local expA = expectedScore(eloA, eloB)
		local dA = roundHalfAwayFromZero(K * (0.5 - expA))
		return dA, -dA
	end
	if result == "A" then
		return EloCalc.compute(eloA, eloB)
	else
		local b, a = EloCalc.compute(eloB, eloA)
		return a, b
	end
end

return EloCalc
