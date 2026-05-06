-- Per-player ownership and equipped state for the non-skin cosmetic
-- categories (kill effects + finishing moves). Skins live in
-- SkinShopService (preserved as-is to avoid migrating the existing
-- PlayerSkins_v2 DataStore). This service uses a single new DataStore
-- "PlayerCosmetics_v1" that stores both categories per player.
--
-- The public surface:
--   CosmeticsService.snapshot(player)           -> { killEffects = ..., finishingMoves = ... }
--   CosmeticsService.grant(player, cat, name)
--   CosmeticsService.equip(player, cat, name)   -- "" unequips
--   CosmeticsService.equipped(player, cat)      -- read by combat hooks
--   CosmeticsService.purchaseWithCoins(player, cat, name) -> ok, reason
--   CosmeticsService.productIdMap()             -- { [productId] = { cat=..., item=... } }
-- StoreService consumes these from a single ProcessReceipt + RemoteFunction.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KillEffectsCatalog = require(ReplicatedStorage.SharedModules.KillEffectsCatalog)
local FinishingMovesCatalog = require(ReplicatedStorage.SharedModules.FinishingMovesCatalog)

local CosmeticsService = {}

local CurrencyService -- injected via init

-- Keyed by category; lets us add/remove categories without touching the
-- per-player state machine. Each category mirrors its ownership/equip
-- to a pair of player attributes ("Owned<Cat>" / "Equipped<Cat>") so the
-- client can react to grants without polling.
local CATEGORIES = {
	killEffects = {
		catalog = KillEffectsCatalog,
		entries = KillEffectsCatalog.Effects,
		order = KillEffectsCatalog.Order,
		ownedAttr = "OwnedKillEffects",
		equippedAttr = "EquippedKillEffect",
	},
	finishingMoves = {
		catalog = FinishingMovesCatalog,
		entries = FinishingMovesCatalog.Moves,
		order = FinishingMovesCatalog.Order,
		ownedAttr = "OwnedFinishingMoves",
		equippedAttr = "EquippedFinishingMove",
	},
}

-- Robux developer product IDs. Fill these in from the Roblox dev dashboard.
-- Until populated, items with productId == 0 fall back to "dev grant"
-- in Studio so designers can preview without spending Robux. The user-facing
-- store still shows the Robux price from the catalog.
CosmeticsService.PRODUCT_IDS = {
	killEffects = {
		Shockwave = 3585282678,
		Inferno   = 3585282768,
		Frostbite = 3585282834,
		Voltage   = 3585282934,
		GoldRush  = 3585283035,
	},
	finishingMoves = {
		Tombstone    = 3585283177,
		RocketLaunch = 3585283234,
		BlackHole    = 3585283343,
		MeteorStrike = 3585283436,
	},
}

local store = DataStoreService:GetDataStore("PlayerCosmetics_v1")
local state = {} -- [userId][cat] = { owned = {[name]=true}, equipped = "" }
local dirty = {} -- [userId] = true means there's an unsaved change

-- Coalesced flush: every 12s, write any dirty player. PlayerRemoving and
-- BindToClose still flush synchronously so nothing is lost on disconnect.
local FLUSH_INTERVAL = 12

local function key(player) return "u_" .. player.UserId end

local function publishCategory(player, cat)
	local cdef = CATEGORIES[cat]
	local s = state[player.UserId] and state[player.UserId][cat]
	if not (cdef and s) then return end
	local list = {}
	for name in pairs(s.owned) do table.insert(list, name) end
	table.sort(list)
	player:SetAttribute(cdef.ownedAttr, table.concat(list, ","))
	player:SetAttribute(cdef.equippedAttr, s.equipped or "")
end

local function publishAll(player)
	for cat in pairs(CATEGORIES) do publishCategory(player, cat) end
end

local function loadPlayer(player)
	local data
	local ok, raw = pcall(function() return store:GetAsync(key(player)) end)
	if ok and type(raw) == "table" then data = raw end

	local s = {}
	for cat, cdef in pairs(CATEGORIES) do
		local owned, equipped = {}, ""
		local catData = data and data[cat]
		if type(catData) == "table" then
			if type(catData.owned) == "table" then
				for _, name in ipairs(catData.owned) do
					if cdef.catalog.exists(name) then owned[name] = true end
				end
			end
			if type(catData.equipped) == "string" and cdef.catalog.exists(catData.equipped)
				and owned[catData.equipped] then
				equipped = catData.equipped
			end
		end
		s[cat] = { owned = owned, equipped = equipped }
	end
	state[player.UserId] = s
	publishAll(player)
end

local function serializeFor(player)
	local s = state[player.UserId]
	if not s then return nil end
	local out = {}
	for cat in pairs(CATEGORIES) do
		local list = {}
		for name in pairs(s[cat].owned) do table.insert(list, name) end
		out[cat] = { owned = list, equipped = s[cat].equipped }
	end
	return out
end

local function savePlayer(userIdOrPlayer)
	local userId = type(userIdOrPlayer) == "number" and userIdOrPlayer or userIdOrPlayer.UserId
	local s = state[userId]
	if not s then return end
	local data = {}
	for cat in pairs(CATEGORIES) do
		local list = {}
		for name in pairs(s[cat].owned) do table.insert(list, name) end
		data[cat] = { owned = list, equipped = s[cat].equipped }
	end
	pcall(function() store:SetAsync("u_" .. userId, data) end)
	dirty[userId] = nil
end

function CosmeticsService.snapshot(player)
	local s = state[player.UserId]
	if not s then return { killEffects = {}, finishingMoves = {} } end
	local out = {}
	for cat, cdef in pairs(CATEGORIES) do
		local items = {}
		for _, name in ipairs(cdef.order) do
			local def = cdef.entries[name]
			table.insert(items, {
				name = name,
				displayName = def.name,
				description = def.description,
				accentColor = def.accentColor,
				robuxPrice = def.robuxPrice,
				coinPrice = def.coinPrice,
				owned = s[cat].owned[name] == true,
				equipped = s[cat].equipped == name,
			})
		end
		out[cat] = { items = items, equipped = s[cat].equipped }
	end
	return out
end

function CosmeticsService.equipped(player, cat)
	local s = state[player.UserId]
	return s and s[cat] and s[cat].equipped or ""
end

function CosmeticsService.grant(player, cat, name)
	local cdef = CATEGORIES[cat]
	if not cdef or not cdef.catalog.exists(name) then return false end
	local s = state[player.UserId]
	if not s then return false end
	if not s[cat].owned[name] then
		s[cat].owned[name] = true
		dirty[player.UserId] = true
	end
	publishCategory(player, cat)
	return true
end

function CosmeticsService.equip(player, cat, name)
	local cdef = CATEGORIES[cat]
	if not cdef then return false, "bad-category" end
	local s = state[player.UserId]
	if not s then return false, "no-session" end
	if name == "" or name == nil then
		s[cat].equipped = ""
	else
		if not cdef.catalog.exists(name) then return false, "bad-item" end
		if not s[cat].owned[name] then return false, "not-owned" end
		s[cat].equipped = name
	end
	publishCategory(player, cat)
	dirty[player.UserId] = true
	return true
end

-- Spend coins, then grant + equip. Returns ok plus a reason on failure
-- so the client UI can surface "not enough coins" vs "already owned".
function CosmeticsService.purchaseWithCoins(player, cat, name)
	local cdef = CATEGORIES[cat]
	if not cdef or not cdef.catalog.exists(name) then return false, "bad-item" end
	local s = state[player.UserId]
	if not s then return false, "no-session" end
	if s[cat].owned[name] then return false, "already-owned" end
	local def = cdef.entries[name]
	local price = def.coinPrice or 0
	if price <= 0 then return false, "no-coin-price" end
	if not CurrencyService then return false, "no-currency" end
	local ok = CurrencyService.spend(player, price)
	if not ok then return false, "insufficient-coins" end
	CosmeticsService.grant(player, cat, name)
	CosmeticsService.equip(player, cat, name)
	return true
end

-- Inverse map { productId -> { cat, item } } so the receipt dispatcher can
-- grant the right cosmetic when a Robux purchase clears.
function CosmeticsService.productIdMap()
	local out = {}
	for cat, items in pairs(CosmeticsService.PRODUCT_IDS) do
		for name, id in pairs(items) do
			if type(id) == "number" and id > 0 then
				out[id] = { category = cat, item = name }
			end
		end
	end
	return out
end

function CosmeticsService.devGrantIfNoProduct(player, cat, name)
	local productId = CosmeticsService.PRODUCT_IDS[cat] and CosmeticsService.PRODUCT_IDS[cat][name]
	if productId and productId > 0 then return false end
	CosmeticsService.grant(player, cat, name)
	CosmeticsService.equip(player, cat, name)
	return true
end

function CosmeticsService.robuxPriceOf(cat, name)
	local cdef = CATEGORIES[cat]
	if not cdef then return 0 end
	local def = cdef.entries[name]
	return def and def.robuxPrice or 0
end

function CosmeticsService.init(currencyService)
	CurrencyService = currencyService
	local function hook(player)
		task.spawn(loadPlayer, player)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
		state[player.UserId] = nil
		dirty[player.UserId] = nil
	end)

	-- Periodic flush coalesces grant/equip writes so back-to-back menu
	-- changes don't each trigger a SetAsync call.
	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			for userId in pairs(dirty) do
				savePlayer(userId)
			end
		end
	end)

	game:BindToClose(function()
		local plist = Players:GetPlayers()
		if #plist == 0 then return end
		local done = 0
		for _, p in ipairs(plist) do
			task.spawn(function()
				savePlayer(p)
				done += 1
			end)
		end
		local deadline = os.clock() + 25
		while done < #plist and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return CosmeticsService
