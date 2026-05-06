local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local StatsService = {}
StatsService.__index = StatsService

local STORE_NAME = "SuperpowerShowdownStats_v1"

local function blank()
	return { wins = 0, losses = 0, draws = 0, streak = 0, bestStreak = 0 }
end

function StatsService.new()
	local self = setmetatable({}, StatsService)
	self._cache = {}
	self._store = nil
	if not RunService:IsStudio() then
		local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
		if ok then self._store = store end
	end
	return self
end

local function key(player) return "u_" .. tostring(player.UserId) end

function StatsService:Load(player)
	local k = key(player)
	if self._cache[k] then return self._cache[k] end
	local stats = blank()
	if self._store then
		local ok, val = pcall(function() return self._store:GetAsync(k) end)
		if ok and type(val) == "table" then
			for fld, default in pairs(blank()) do
				if type(val[fld]) == "number" then stats[fld] = val[fld] else stats[fld] = default end
			end
		end
	end
	self._cache[k] = stats
	return stats
end

function StatsService:Save(player)
	local k = key(player)
	local stats = self._cache[k]
	if not stats then return end
	if self._store then
		pcall(function() self._store:SetAsync(k, stats) end)
	end
end

function StatsService:Get(player)
	return self:Load(player)
end

function StatsService:Push(player)
	if player and player.Parent then
		Remotes.StatsUpdated:FireClient(player, self:Get(player))
	end
end

-- result: "win" / "lose" / "draw"
function StatsService:Record(player, result)
	local s = self:Load(player)
	if result == "win" then
		s.wins += 1
		s.streak += 1
		if s.streak > s.bestStreak then s.bestStreak = s.streak end
	elseif result == "lose" then
		s.losses += 1
		s.streak = 0
	else
		s.draws += 1
	end
	self:Save(player)
	self:Push(player)
	return s
end

function StatsService:WinRate(player)
	local s = self:Load(player)
	local total = s.wins + s.losses
	if total == 0 then return 0 end
	return s.wins / total
end

return StatsService
