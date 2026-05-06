-- Per-player Coins balance + bonus eligibility, persisted in DataStore
-- "PlayerCoins_v1" and mirrored to the player as the "Coins" attribute
-- (which the client reads to populate the store header).
--
-- Schema:
--   * Legacy records are a bare number (coin balance only). Loader
--     migrates these on read by treating them as { coins = N, welcomed
--     = true } — no retroactive welcome bonus for existing players, but
--     they DO start collecting daily bonuses going forward.
--   * Current records are a table:
--       { coins = N, lastDailyUTC = "YYYY-MM-DD", welcomed = true }
--
-- Mutations go through add()/spend(). Saves are coalesced via a periodic
-- flush so back-to-back coin awards don't exhaust the SetAsync budget.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyService = {}

local store = DataStoreService:GetDataStore("PlayerCoins_v1")
local accounts = {} -- [userId] = { coins, lastDailyUTC, welcomed }
local loaded = {}   -- [userId] = true once initial load finished
local dirty = {}    -- [userId] = true means there's an unsaved change

local FLUSH_INTERVAL = 12

-- Bonus economy. Welcome is a one-time first-load boost so brand-new
-- players see the store as REACHABLE (10% of a skin's price) rather than
-- a wall. Daily is a smaller recurring nudge to drive retention — Roblox's
-- discovery surfaces lean heavily on day-2 / day-7 retention curves.
local WELCOME_BONUS = 500
local DAILY_BONUS = 75

-- Lazily wait for the bonus event so this module loads in either
-- bootstrap order (Remotes folder is created at server start, but the
-- specific RemoteEvent might be added/replaced after CurrencyService
-- requires).
local BonusGranted

local function utcDate()
	-- "YYYY-MM-DD" in UTC. Players in different time zones cross "midnight"
	-- on the same wall-clock instant, which keeps the bonus globally fair
	-- (no zone-shopping for a second daily claim).
	return os.date("!%Y-%m-%d")
end

local function publish(player)
	if not player.Parent then return end
	local acct = accounts[player.UserId]
	player:SetAttribute("Coins", acct and acct.coins or 0)
end

local function loadPlayer(player)
	local acct = { coins = 0, lastDailyUTC = nil, welcomed = false }
	local ok, data = pcall(function() return store:GetAsync("u_" .. player.UserId) end)
	if ok then
		if type(data) == "number" then
			-- Legacy record (bare balance). Mark as already welcomed so we
			-- don't retroactively grant a welcome bonus to existing players.
			acct.coins = data
			acct.welcomed = true
		elseif type(data) == "table" then
			acct.coins = type(data.coins) == "number" and data.coins or 0
			acct.lastDailyUTC = type(data.lastDailyUTC) == "string" and data.lastDailyUTC or nil
			acct.welcomed = data.welcomed == true
		end
	end
	accounts[player.UserId] = acct
	loaded[player.UserId] = true
	publish(player)
end

local function savePlayerNow(userId)
	local acct = accounts[userId]
	if not acct then return end
	pcall(function()
		store:SetAsync("u_" .. userId, {
			coins = acct.coins,
			lastDailyUTC = acct.lastDailyUTC,
			welcomed = acct.welcomed,
		})
	end)
	dirty[userId] = nil
end

local function fireBonus(player, kind, amount)
	if not BonusGranted then return end
	BonusGranted:FireClient(player, { kind = kind, amount = amount })
end

function CurrencyService.get(player)
	local acct = accounts[player.UserId]
	return acct and acct.coins or 0
end

function CurrencyService.add(player, amount)
	if not loaded[player.UserId] then return false end
	if type(amount) ~= "number" or amount <= 0 then return false end
	local acct = accounts[player.UserId]
	acct.coins = acct.coins + math.floor(amount)
	publish(player)
	dirty[player.UserId] = true
	return true
end

-- Returns true and deducts only if the player has at least `amount` coins.
function CurrencyService.spend(player, amount)
	if not loaded[player.UserId] then return false end
	if type(amount) ~= "number" or amount <= 0 then return false end
	amount = math.floor(amount)
	local acct = accounts[player.UserId]
	if acct.coins < amount then return false end
	acct.coins = acct.coins - amount
	publish(player)
	dirty[player.UserId] = true
	return true
end

-- One-time first-load grant. Returns coins awarded (0 if already welcomed).
function CurrencyService.tryClaimWelcome(player)
	if not loaded[player.UserId] then return 0 end
	local acct = accounts[player.UserId]
	if acct.welcomed then return 0 end
	acct.welcomed = true
	acct.coins = acct.coins + WELCOME_BONUS
	publish(player)
	dirty[player.UserId] = true
	fireBonus(player, "welcome", WELCOME_BONUS)
	return WELCOME_BONUS
end

-- Daily UTC-day grant. Returns coins awarded (0 if already claimed today).
function CurrencyService.tryClaimDaily(player)
	if not loaded[player.UserId] then return 0 end
	local acct = accounts[player.UserId]
	local today = utcDate()
	if acct.lastDailyUTC == today then return 0 end
	acct.lastDailyUTC = today
	acct.coins = acct.coins + DAILY_BONUS
	publish(player)
	dirty[player.UserId] = true
	fireBonus(player, "daily", DAILY_BONUS)
	return DAILY_BONUS
end

function CurrencyService.init()
	BonusGranted = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("BonusGranted")

	local function hook(player)
		task.spawn(function()
			loadPlayer(player)
			-- Welcome first (one-shot), then daily. Both fire BonusGranted
			-- so the client toast can stack two messages on a brand-new
			-- player who joins on the same UTC day they registered.
			CurrencyService.tryClaimWelcome(player)
			CurrencyService.tryClaimDaily(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	Players.PlayerRemoving:Connect(function(player)
		savePlayerNow(player.UserId)
		accounts[player.UserId] = nil
		loaded[player.UserId] = nil
		dirty[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			for userId in pairs(dirty) do
				savePlayerNow(userId)
			end
		end
	end)

	game:BindToClose(function()
		local plist = Players:GetPlayers()
		if #plist == 0 then return end
		local done = 0
		for _, p in ipairs(plist) do
			task.spawn(function()
				savePlayerNow(p.UserId)
				done += 1
			end)
		end
		local deadline = os.clock() + 25
		while done < #plist and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return CurrencyService
