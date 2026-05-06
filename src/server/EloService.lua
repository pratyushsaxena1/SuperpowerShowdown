local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ranks = require(Shared:WaitForChild("Ranks"))

local EloService = {}
EloService.__index = EloService

local STORE_NAME = "SuperpowerShowdownElo_v1"
local LB_NAME    = "SuperpowerShowdownEloLeaderboard_v1" -- OrderedDataStore for top players

function EloService.new()
	local self = setmetatable({}, EloService)
	self._cache = {}
	self._store = nil
	self._leaderboard = nil
	if not RunService:IsStudio() then
		local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
		if ok then self._store = store end
		local ok2, lb = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, LB_NAME)
		if ok2 then self._leaderboard = lb end
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
	if self._leaderboard then
		pcall(function() self._leaderboard:SetAsync(tostring(player.UserId), elo) end)
	end
end

function EloService:Get(player)
	return self:Load(player)
end

function EloService:GetRank(player)
	return Ranks.fromElo(self:Get(player))
end

function EloService:Set(player, elo)
	self._cache[key(player)] = elo
end

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

-- Returns array of { userId, name, elo } sorted descending. Falls back to in-memory
-- top players when no leaderboard datastore is available (Studio).
function EloService:GetTop(count)
	count = count or 10
	if self._leaderboard then
		local ok, page = pcall(function()
			return self._leaderboard:GetSortedAsync(false, count)
		end)
		if ok and page then
			local entries = page:GetCurrentPage()
			local Players = game:GetService("Players")
			local out = {}
			for _, e in ipairs(entries) do
				local userId = tonumber(e.key)
				local name = "Player" .. tostring(userId)
				local ok2, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
				if ok2 and n then name = n end
				table.insert(out, { userId = userId, name = name, elo = e.value })
			end
			return out
		end
	end
	-- Fallback: live players in the server.
	local Players = game:GetService("Players")
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(out, { userId = p.UserId, name = p.Name, elo = self:Get(p) })
	end
	table.sort(out, function(a, b) return a.elo > b.elo end)
	while #out > count do table.remove(out) end
	return out
end

return EloService
