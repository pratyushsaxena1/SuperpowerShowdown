local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local EloService = {}
EloService.__index = EloService

local STORE_NAME = "SuperpowerShowdownElo_v1"

function EloService.new()
	local self = setmetatable({}, EloService)
	self._cache = {}
	self._store = nil
	if not RunService:IsStudio() then
		local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
		if ok then self._store = store end
	end
	return self
end

local function key(player)
	return "u_" .. tostring(player.UserId)
end

function EloService:Load(player)
	local k = key(player)
	if self._cache[k] then return self._cache[k] end
	local elo = Config.DEFAULT_ELO
	if self._store then
		local ok, val = pcall(function() return self._store:GetAsync(k) end)
		if ok and type(val) == "number" then elo = val end
	end
	self._cache[k] = elo
	return elo
end

function EloService:Save(player)
	local k = key(player)
	local elo = self._cache[k]
	if not elo then return end
	if self._store then
		pcall(function() self._store:SetAsync(k, elo) end)
	end
end

function EloService:Get(player)
	return self:Load(player)
end

function EloService:Set(player, elo)
	self._cache[key(player)] = elo
end

-- Returns delta to apply to winner; loser gets the negated delta. result: "win" / "draw" — perspective of `a`.
function EloService:ComputeDeltas(eloA, eloB, result)
	if result == "draw" then
		return 0, 0
	end
	local winnerElo = result == "win" and eloA or eloB
	local loserElo  = result == "win" and eloB or eloA
	local gap = winnerElo - loserElo
	local delta
	if math.abs(gap) <= Config.ELO_FAVORED_GAP then
		delta = Config.ELO_DELTAS.equal
	elseif gap > 0 then
		delta = Config.ELO_DELTAS.favored
	else
		delta = Config.ELO_DELTAS.upset
	end
	if result == "win" then
		return delta, -delta
	else
		return -delta, delta
	end
end

function EloService:ApplyMatch(playerA, playerB, winner)
	local eloA = self:Get(playerA)
	local eloB = self:Get(playerB)
	local result
	if winner == nil then
		result = "draw"
	elseif winner == playerA then
		result = "win"
	else
		result = "lose"
	end
	local dA, dB = self:ComputeDeltas(eloA, eloB, result)
	local newA = math.max(0, eloA + dA)
	local newB = math.max(0, eloB + dB)
	self:Set(playerA, newA)
	self:Set(playerB, newB)
	self:Save(playerA)
	self:Save(playerB)
	return newA, newB, dA, dB
end

return EloService
