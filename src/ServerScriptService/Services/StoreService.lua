-- Unified store backend. Owns:
--   * the ProcessReceipt callback for ALL Robux purchases
--     (skins, kill effects, finishing moves, coin packs)
--   * the StoreAction RemoteFunction (the single client→server entry point)
--   * the OpenStore RemoteEvent (server-fired from lobby ProximityPrompts)
--
-- Per-category state lives in the source-of-truth services:
--   * SkinShopService for skins
--   * CosmeticsService for kill effects + finishing moves
--   * CurrencyService for coins
-- This service is a thin dispatcher; it does not hold its own DataStore.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenStore = Remotes:WaitForChild("OpenStore")
local StoreAction = Remotes:WaitForChild("StoreAction")

local StoreService = {}

local SkinShopService
local CosmeticsService
local CurrencyService

-- Coin packs: Robux developer products that grant in-game Coins. Each
-- pack's R$/coin ratio is intentionally worse than buying an item
-- directly with Robux, so direct Robux purchases stay the best deal.
StoreService.COIN_PACKS = {
	{ key = "starter",  robux = 100,  coins = 500,  productId = 3585282039 },
	{ key = "standard", robux = 250,  coins = 1500, productId = 3585282241 },
	{ key = "premium",  robux = 500,  coins = 3500, productId = 3585282356 },
	{ key = "mega",     robux = 1000, coins = 8000, productId = 3585282452 },
}

local function findCoinPack(productId)
	for _, pack in ipairs(StoreService.COIN_PACKS) do
		if pack.productId == productId and productId > 0 then return pack end
	end
	return nil
end

-- ProcessReceipt only fires once Robux has actually been spent. This
-- function must idempotently grant the matching item — Roblox may retry
-- a receipt if our return value can't be persisted, and double-granting
-- a skin or coin pack would be visible as a duplicate refund line.
local pendingReceipts = {}
local function processReceipt(receiptInfo)
	if pendingReceipts[receiptInfo.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productId = receiptInfo.ProductId

	local skinMap = SkinShopService.productIdMap()
	local skinName = skinMap[productId]
	if skinName then
		SkinShopService.grantSkin(player, skinName)
		SkinShopService.equipSkin(player, skinName)
		pendingReceipts[receiptInfo.PurchaseId] = true
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local cosmeticMap = CosmeticsService.productIdMap()
	local cosmetic = cosmeticMap[productId]
	if cosmetic then
		CosmeticsService.grant(player, cosmetic.category, cosmetic.item)
		CosmeticsService.equip(player, cosmetic.category, cosmetic.item)
		pendingReceipts[receiptInfo.PurchaseId] = true
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local pack = findCoinPack(productId)
	if pack then
		CurrencyService.add(player, pack.coins)
		pendingReceipts[receiptInfo.PurchaseId] = true
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Not one of ours — leave it pending so other ProcessReceipt handlers
	-- (or a future redeploy that knows about this product) can claim it.
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function buildSnapshot(player)
	local cosmetic = CosmeticsService.snapshot(player)
	return {
		coins = CurrencyService.get(player),
		skins = SkinShopService.snapshot(player),
		killEffects = cosmetic.killEffects,
		finishingMoves = cosmetic.finishingMoves,
		coinPacks = StoreService.COIN_PACKS,
		inMatch = player:GetAttribute("InMatch") and true or false,
	}
end

StoreService.buildSnapshot = buildSnapshot

local function actionRefresh(player)
	return { ok = true, state = buildSnapshot(player) }
end

local function actionEquipSkin(player, payload)
	local ok, reason = SkinShopService.equipSkin(player, payload.item or "")
	return { ok = ok, reason = reason, state = buildSnapshot(player) }
end

local function actionEquipCosmetic(player, payload)
	local ok, reason = CosmeticsService.equip(player, payload.category, payload.item or "")
	return { ok = ok, reason = reason, state = buildSnapshot(player) }
end

local function actionBuySkin(player, payload)
	local skin = payload.item
	if not skin then return { ok = false, reason = "bad-item" } end
	if payload.payWith == "coins" then
		local ok, reason = SkinShopService.purchaseWithCoins(player, skin)
		return { ok = ok, reason = reason, state = buildSnapshot(player) }
	end
	-- Robux path: dev-grant if there's no product ID, otherwise prompt.
	if SkinShopService.devGrantIfNoProduct(player, skin) then
		return { ok = true, reason = "dev-grant", state = buildSnapshot(player) }
	end
	if SkinShopService.promptRobuxPurchase(player, skin) then
		return { ok = true, reason = "prompted", state = buildSnapshot(player) }
	end
	return { ok = false, reason = "no-purchase-path" }
end

local function actionBuyCosmetic(player, payload)
	local cat = payload.category
	local item = payload.item
	if not (cat and item) then return { ok = false, reason = "bad-payload" } end
	if payload.payWith == "coins" then
		local ok, reason = CosmeticsService.purchaseWithCoins(player, cat, item)
		return { ok = ok, reason = reason, state = buildSnapshot(player) }
	end
	if CosmeticsService.devGrantIfNoProduct(player, cat, item) then
		return { ok = true, reason = "dev-grant", state = buildSnapshot(player) }
	end
	local productId = CosmeticsService.PRODUCT_IDS[cat] and CosmeticsService.PRODUCT_IDS[cat][item]
	if productId and productId > 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
		return { ok = true, reason = "prompted", state = buildSnapshot(player) }
	end
	return { ok = false, reason = "no-purchase-path" }
end

local function actionBuyCoinPack(player, payload)
	local key = payload.item
	for _, pack in ipairs(StoreService.COIN_PACKS) do
		if pack.key == key then
			if pack.productId and pack.productId > 0 then
				MarketplaceService:PromptProductPurchase(player, pack.productId)
				return { ok = true, reason = "prompted", state = buildSnapshot(player) }
			else
				-- Dev fallback: grant the coins directly so designers can
				-- exercise the rest of the store without setting up a
				-- product. Live builds set productId.
				CurrencyService.add(player, pack.coins)
				return { ok = true, reason = "dev-grant", state = buildSnapshot(player) }
			end
		end
	end
	return { ok = false, reason = "bad-pack" }
end

local function onStoreAction(player, payload)
	if type(payload) ~= "table" then return { ok = false, reason = "bad-payload" } end
	local action = payload.action
	local category = payload.category
	if action == "refresh" then return actionRefresh(player) end

	if action == "equip" then
		if category == "skins" then return actionEquipSkin(player, payload) end
		if category == "killEffects" or category == "finishingMoves" then
			return actionEquipCosmetic(player, payload)
		end
		return { ok = false, reason = "bad-category" }
	end

	if action == "buy" then
		if category == "skins" then return actionBuySkin(player, payload) end
		if category == "killEffects" or category == "finishingMoves" then
			return actionBuyCosmetic(player, payload)
		end
		if category == "coins" then return actionBuyCoinPack(player, payload) end
		return { ok = false, reason = "bad-category" }
	end

	return { ok = false, reason = "unknown-action" }
end

function StoreService.init(skinShopService, cosmeticsService, currencyService)
	SkinShopService = skinShopService
	CosmeticsService = cosmeticsService
	CurrencyService = currencyService

	MarketplaceService.ProcessReceipt = processReceipt
	StoreAction.OnServerInvoke = onStoreAction
end

function StoreService.registerLobby(lobbyModel)
	for _, desc in ipairs(lobbyModel:GetDescendants()) do
		if desc.Name == "BuyPrompt" and desc:IsA("ProximityPrompt") then
			desc.ActionText = "Open Store"
			desc.ObjectText = "Store"
			desc.Triggered:Connect(function(player)
				OpenStore:FireClient(player, buildSnapshot(player))
			end)
		end
	end
end

return StoreService
