-- Per-player skin ownership and equipped state. Persists to DataStore
-- "PlayerSkins_v2" (name kept stable so live player data isn't migrated).
--
-- This service used to own the ProcessReceipt callback and the
-- SkinShopAction RemoteFunction directly. With the unified store (skins +
-- kill effects + finishing moves + coin packs), those concerns moved to
-- StoreService, which calls the public APIs below to grant/equip/spend.
-- The OpenSkinShop/SkinShopAction remotes stay in place for backward
-- compatibility with anything that still listens for them, but new code
-- should go through StoreService.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinCatalog = require(ReplicatedStorage.SharedModules.SkinCatalog)

local SkinShopService = {}

local CurrencyService -- injected via init

-- Map skin name -> Roblox developer product ID. Existing live products.
SkinShopService.PRODUCT_IDS = {
	Fire = 3579477730,
	Ice  = 3579477829,
	Neon = 3579477855,
	Gold = 3579477889,
}

local skinStore = DataStoreService:GetDataStore("PlayerSkins_v2")
local playerState = {} -- [userId] = { owned = { skin = true }, equipped = string }
local dirty = {} -- [userId] = true means there's an unsaved change

-- Coalesced flush: every 12s, write any dirty player. PlayerRemoving and
-- BindToClose still flush synchronously so nothing is lost on disconnect.
local FLUSH_INTERVAL = 12

local function key(player) return "u_" .. player.UserId end

local function publishAttributes(player)
	local st = playerState[player.UserId]
	if not st then return end
	local list = {}
	for name in pairs(st.owned) do table.insert(list, name) end
	table.sort(list)
	player:SetAttribute("OwnedSkins", table.concat(list, ","))
	player:SetAttribute("EquippedSkin", st.equipped or "")
end

local function loadPlayer(player)
	local state = { owned = {}, equipped = "" }
	local ok, data = pcall(function() return skinStore:GetAsync(key(player)) end)
	if ok and type(data) == "table" then
		if type(data.owned) == "table" then
			for _, s in ipairs(data.owned) do
				if SkinCatalog.exists(s) then state.owned[s] = true end
			end
		end
		if type(data.equipped) == "string" and SkinCatalog.exists(data.equipped)
			and state.owned[data.equipped] then
			state.equipped = data.equipped
		end
	end
	playerState[player.UserId] = state
	publishAttributes(player)
end

local function savePlayer(userIdOrPlayer)
	local userId = type(userIdOrPlayer) == "number" and userIdOrPlayer or userIdOrPlayer.UserId
	local st = playerState[userId]
	if not st then return end
	local ownedList = {}
	for name in pairs(st.owned) do table.insert(ownedList, name) end
	pcall(function()
		skinStore:SetAsync("u_" .. userId, { owned = ownedList, equipped = st.equipped })
	end)
	dirty[userId] = nil
end

local function applyToCharacter(player)
	local char = player.Character
	if not char then return end
	local st = playerState[player.UserId]
	if not st then return end
	-- Let Humanoid/Animate finish their own setup before we overwrite colors.
	task.wait(0.2)
	if player.Character == char and char.Parent then
		SkinCatalog.apply(char, st.equipped ~= "" and st.equipped or nil)
	end
end

function SkinShopService.grantSkin(player, skinName)
	local st = playerState[player.UserId]
	if not st or not SkinCatalog.exists(skinName) then return false end
	if not st.owned[skinName] then
		st.owned[skinName] = true
		dirty[player.UserId] = true
	end
	publishAttributes(player)
	return true
end

function SkinShopService.equipSkin(player, skinName)
	local st = playerState[player.UserId]
	if not st then return false, "no-session" end
	if skinName ~= "" and not st.owned[skinName] then return false, "not-owned" end
	if skinName ~= "" and not SkinCatalog.exists(skinName) then return false, "bad-skin" end
	st.equipped = skinName
	publishAttributes(player)
	dirty[player.UserId] = true
	applyToCharacter(player)
	return true
end

function SkinShopService.purchaseWithCoins(player, skinName)
	if not SkinCatalog.exists(skinName) then return false, "bad-skin" end
	local st = playerState[player.UserId]
	if not st then return false, "no-session" end
	if st.owned[skinName] then return false, "already-owned" end
	local price = SkinCatalog.coinPriceOf(skinName)
	if price <= 0 then return false, "no-coin-price" end
	if not CurrencyService then return false, "no-currency" end
	local ok = CurrencyService.spend(player, price)
	if not ok then return false, "insufficient-coins" end
	SkinShopService.grantSkin(player, skinName)
	SkinShopService.equipSkin(player, skinName)
	return true
end

function SkinShopService.snapshot(player)
	local st = playerState[player.UserId] or { owned = {}, equipped = "" }
	local skins = {}
	for _, name in ipairs(SkinCatalog.Order) do
		local def = SkinCatalog.Skins[name]
		table.insert(skins, {
			name = name,
			displayName = def.name,
			robuxPrice = def.price,
			coinPrice = def.coinPrice,
			description = def.description,
			accentColor = def.accentColor,
			owned = st.owned[name] == true,
			equipped = st.equipped == name,
		})
	end
	return { items = skins, equipped = st.equipped }
end

-- Inverse map of PRODUCT_IDS for ProcessReceipt dispatch.
function SkinShopService.productIdMap()
	local out = {}
	for name, id in pairs(SkinShopService.PRODUCT_IDS) do
		if type(id) == "number" and id > 0 then
			out[id] = name
		end
	end
	return out
end

-- Dev fallback: when a skin has no real product ID configured, treat the
-- buy click as an instant grant so designers can preview without the
-- Robux prompt.
function SkinShopService.devGrantIfNoProduct(player, skinName)
	local productId = SkinShopService.PRODUCT_IDS[skinName]
	if productId and productId > 0 then return false end
	SkinShopService.grantSkin(player, skinName)
	SkinShopService.equipSkin(player, skinName)
	return true
end

function SkinShopService.promptRobuxPurchase(player, skinName)
	local productId = SkinShopService.PRODUCT_IDS[skinName]
	if not productId or productId <= 0 then return false end
	MarketplaceService:PromptProductPurchase(player, productId)
	return true
end

function SkinShopService.init(currencyService)
	CurrencyService = currencyService

	local function hookPlayer(player)
		loadPlayer(player)
		player.CharacterAdded:Connect(function()
			applyToCharacter(player)
		end)
		if player.Character then
			task.spawn(applyToCharacter, player)
		end
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
		playerState[player.UserId] = nil
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

	-- Flush every in-session player's skin data before the server actually
	-- shuts down. PlayerRemoving races the shutdown otherwise, so recent
	-- purchases/equips could be lost on a crash or BindToClose timeout.
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

return SkinShopService
