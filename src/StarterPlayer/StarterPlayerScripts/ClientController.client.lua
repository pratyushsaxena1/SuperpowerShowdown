local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

-- Hide Roblox's default health bar in the top-right; we draw our own bottom
-- HUD bars during a match. SetCoreGuiEnabled can fail for a few seconds at
-- session start, so retry until it sticks.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then return end
		task.wait(0.5)
	end
end)

-- Apply interior lighting on the client immediately. The server's
-- LobbyBuilder also sets these, but Lighting properties replicate with a
-- noticeable delay on first join, so the lobby would briefly look dim
-- without this client-side bootstrap.
do
	local Lighting = game:GetService("Lighting")
	Lighting.Ambient = Color3.fromRGB(160, 155, 175)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 145)
	Lighting.Brightness = 3
	Lighting.GlobalShadows = false
	Lighting.FogStart = 200
	Lighting.FogEnd = 600
	Lighting.FogColor = Color3.fromRGB(40, 40, 60)
	Lighting.ExposureCompensation = 0.7
end

local SharedModules = ReplicatedStorage:WaitForChild("SharedModules")
local AbilityDefs = require(SharedModules:WaitForChild("AbilityDefs"))
local GameConfig = require(SharedModules:WaitForChild("GameConfig"))
local Ranks = require(SharedModules:WaitForChild("Ranks"))

local RemotesFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local Remotes = {
	ShowAbilitySelection = RemotesFolder:WaitForChild("ShowAbilitySelection"),
	AbilitySelected = RemotesFolder:WaitForChild("AbilitySelected"),
	MatchCountdown = RemotesFolder:WaitForChild("MatchCountdown"),
	MatchStarted = RemotesFolder:WaitForChild("MatchStarted"),
	MatchEnded = RemotesFolder:WaitForChild("MatchEnded"),
	HealthUpdate = RemotesFolder:WaitForChild("HealthUpdate"),
	TimerUpdate = RemotesFolder:WaitForChild("TimerUpdate"),
	DamageNumber = RemotesFolder:WaitForChild("DamageNumber"),
	AbilityEffect = RemotesFolder:WaitForChild("AbilityEffect"),
	EloUpdated = RemotesFolder:WaitForChild("EloUpdated"),
	RequestAbilityActivation = RemotesFolder:WaitForChild("RequestAbilityActivation"),
	RequestBasicAttack = RemotesFolder:WaitForChild("RequestBasicAttack"),
	OpenSkinShop = RemotesFolder:WaitForChild("OpenSkinShop"),
	SkinShopAction = RemotesFolder:WaitForChild("SkinShopAction"),
	OpenStore = RemotesFolder:WaitForChild("OpenStore"),
	StoreAction = RemotesFolder:WaitForChild("StoreAction"),
	BonusGranted = RemotesFolder:WaitForChild("BonusGranted"),
	BroadcastNotification = RemotesFolder:WaitForChild("BroadcastNotification"),
	GetTopPlayers = RemotesFolder:WaitForChild("GetTopPlayers"),
}

local SkinCatalog = require(SharedModules:WaitForChild("SkinCatalog"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("DuelHUD")

local state = {
	ability = nil,
	inMatch = false,
	activeUntil = 0,    -- while now < activeUntil: ability is still running, hide CD overlay
	cooldownUntil = 0,  -- while activeUntil <= now < cooldownUntil: show CD countdown
	cooldownTotal = 0,  -- used to normalize the CD bar fill
}

-- Forward-declared so the MatchStarted handler can preload the punch
-- animation on the player's character; the actual implementation lives near
-- the punch VFX further down.
local getPunchTrack
local lastSelfHealth

local function make(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do inst[k] = v end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	return inst
end

local function corner(r) return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }) end
local function stroke(thickness, color)
	return make("UIStroke", { Thickness = thickness or 2, Color = color or Color3.fromRGB(0, 0, 0) })
end

local function buildHUD()
	hud:ClearAllChildren()

	-- Top strip: just a centered match timer. Per-player Elo lives on the
	-- nametag billboard, so no corner labels.
	local top = make("Frame", {
		Name = "TopBar", Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1, Parent = hud,
	})

	make("TextLabel", { Name = "Timer", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.new(0, 120, 0, 44),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.4, TextSize = 32, Text = "",
		Parent = top })

	-- Bottom cluster: health bars left/right, compact ability box in the
	-- middle, thin controls strip beneath everything.
	local bottom = make("Frame", {
		Name = "BottomBar", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -40, 0, 96),
		BackgroundTransparency = 1, Parent = hud,
	})

	local function buildHealth(name, anchor, posX, fillColor, nameText, nameAlign, nameColor)
		local frame = make("Frame", {
			Name = name, AnchorPoint = anchor, Position = UDim2.new(posX, 0, 0, 0),
			Size = UDim2.new(0, 340, 0, 32),
			BackgroundColor3 = Color3.fromRGB(10, 10, 18), BackgroundTransparency = 0.15,
			BorderSizePixel = 0, Visible = false, Parent = bottom,
		}, {
			corner(8),
			make("Frame", { Name = "Bar", Size = UDim2.new(1, 0, 1, 0),
				BackgroundColor3 = fillColor, BorderSizePixel = 0 }, { corner(8) }),
		})
		local label = make("TextLabel", {
			Name = "Label", Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 15, Text = "100 / 100", Parent = frame,
		})
		local ls = Instance.new("UIStroke")
		ls.Thickness = 2
		ls.Color = Color3.fromRGB(0, 0, 0)
		ls.Transparency = 0.3
		ls.Parent = label
		make("TextLabel", {
			Name = "NameTag", Position = UDim2.new(0, 0, 0, -18),
			Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
			Font = Enum.Font.Gotham, TextColor3 = nameColor,
			TextXAlignment = nameAlign, TextSize = 12, Text = nameText,
			Parent = frame,
		})
		return frame
	end

	buildHealth("SelfHealth", Vector2.new(0, 0), 0,
		Color3.fromRGB(80, 220, 120), "YOU",
		Enum.TextXAlignment.Left, Color3.fromRGB(180, 255, 200))
	buildHealth("OpponentHealth", Vector2.new(1, 0), 1,
		Color3.fromRGB(220, 80, 80), "OPPONENT",
		Enum.TextXAlignment.Right, Color3.fromRGB(255, 190, 190))

	-- Compact ability box between the two health bars. Holds the ability
	-- name/key and acts as the cooldown surface.
	local iconBox = make("Frame", { Name = "AbilityBox", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0, 200, 0, 52),
		BackgroundColor3 = Color3.fromRGB(40, 40, 50), BackgroundTransparency = 0.2,
		Visible = false, Parent = bottom },
		{ corner(8), stroke(1, Color3.fromRGB(80, 80, 95)) })

	make("TextLabel", { Name = "AbilityName", Size = UDim2.new(1, -12, 0, 24),
		Position = UDim2.new(0, 6, 0, 4), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16, Text = "", Parent = iconBox })

	make("TextLabel", { Name = "AbilityKey", Position = UDim2.new(0, 6, 0, 28),
		Size = UDim2.new(1, -12, 0, 20), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(200, 200, 215),
		TextSize = 13, Text = "[ E ]", Parent = iconBox })

	-- Cooldown overlay sweeps top→bottom as the cooldown ticks.
	local cdOverlay = make("Frame", { Name = "CooldownOverlay", Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.5,
		Visible = false, Active = false, ZIndex = 5, Parent = iconBox }, { corner(8) })
	make("TextLabel", { Name = "CooldownText", Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 22,
		Text = "", ZIndex = 6, Parent = cdOverlay })

	-- Thin controls strip under the bottom row.
	local controls = make("Frame", { Name = "Controls", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0, 360, 0, 18),
		BackgroundTransparency = 1, Visible = false, Parent = bottom })
	make("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(200, 200, 215),
		TextSize = 12, Text = "LEFT-CLICK = Attack    •    E = Ability",
		Parent = controls })

	-- Match-start countdown. Light font weight + no text stroke so it
	-- doesn't read as oppressively bold.
	make("TextLabel", { Name = "Countdown", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 320, 0, 110),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
		TextColor3 = Color3.fromRGB(245, 245, 250),
		TextStrokeTransparency = 1, TextSize = 80, Text = "",
		Visible = false, Parent = hud })

	-- Centered welcome banner above the player. Wider with a tighter
	-- vertical layout so the title and the two instruction lines sit in
	-- a clean three-row stack. Lives 12s then fades.
	local welcome = make("Frame", { Name = "Welcome", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.new(0, 540, 0, 116),
		BackgroundColor3 = Color3.fromRGB(18, 20, 32), BackgroundTransparency = 0.1,
		Parent = hud }, { corner(12), stroke(1, Color3.fromRGB(80, 80, 110)) })
	make("Frame", { Name = "Accent", Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Color3.fromRGB(255, 220, 110), BorderSizePixel = 0,
		Parent = welcome }, { corner(2) })
	make("TextLabel", { Size = UDim2.new(1, -24, 0, 28), Position = UDim2.new(0, 12, 0, 12),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(245, 230, 170), TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Welcome to Superpower Showdown", Parent = welcome })
	make("TextLabel", { Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 0, 46),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(220, 220, 240), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Step on a colored duel pad — matching colors play each other.", Parent = welcome })
	make("TextLabel", { Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 0, 68),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(170, 245, 180), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Or step on the green pad to train against an AI bot.", Parent = welcome })
	make("TextLabel", { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.new(0, 12, 0, 90),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(150, 150, 175), TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "LEFT-CLICK to attack    •    E for ability    •    TAB for top players",
		Parent = welcome })
	task.delay(12, function()
		if welcome and welcome.Parent then
			TweenService:Create(welcome, TweenInfo.new(0.4),
				{ BackgroundTransparency = 1 }):Play()
			task.wait(0.45)
			if welcome.Parent then welcome:Destroy() end
		end
	end)
end

buildHUD()

local function setBar(frame, pct, label)
	frame.Bar.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
	frame.Label.Text = label
end

Remotes.HealthUpdate.OnClientEvent:Connect(function(payload)
	local bar = payload.target == "self" and hud.BottomBar.SelfHealth or hud.BottomBar.OpponentHealth
	local hp = math.max(0, math.floor(payload.health or 0))
	local mx = math.max(1, math.floor(payload.max or 100))
	setBar(bar, hp / mx, hp .. " / " .. mx)
end)

Remotes.TimerUpdate.OnClientEvent:Connect(function(remaining)
	hud.TopBar.Timer.Text = tostring(math.ceil(remaining))
end)

local selectionGui

local function openAbilitySelect(info)
	if selectionGui then selectionGui:Destroy() end

	-- Dim backdrop so the menu reads as modal.
	selectionGui = make("Frame", {
		Name = "AbilitySelect", Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.5,
		BorderSizePixel = 0, ZIndex = 80, Parent = hud,
	})

	-- Card is 1280 wide so a 6-column grid (6 * 192 + 5 * 10 = 1202 cells)
	-- fits cleanly with breathing room either side. Height stays at 540 —
	-- 12 abilities = 6×2, no orphaned third row.
	local card = make("Frame", {
		Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 1280, 0, 540),
		BackgroundColor3 = Color3.fromRGB(18, 18, 28), BackgroundTransparency = 0.05,
		BorderSizePixel = 0, ZIndex = 81, Parent = selectionGui,
	}, { corner(14), stroke(1, Color3.fromRGB(80, 80, 110)) })

	-- Title row: big title left, vs-opponent context right. Same medium
	-- weight + lighter color used by the Store header so the modal looks
	-- like part of the same product, not a separate UI era.
	make("TextLabel", {
		Name = "Title", AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 600, 0, 30), Position = UDim2.new(0.5, 0, 0, 22),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(245, 230, 170), TextSize = 22,
		Text = "Choose your power", TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 82, Parent = card,
	})
	make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 600, 0, 16), Position = UDim2.new(0.5, 0, 0, 56),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(170, 170, 190), TextSize = 12,
		Text = "Click any ability — auto-picks if you wait too long.",
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 82, Parent = card,
	})

	local opponentBox = make("Frame", {
		Name = "Opponent", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -22, 0, 22), Size = UDim2.new(0, 220, 0, 64),
		BackgroundColor3 = Color3.fromRGB(28, 28, 42), BackgroundTransparency = 0.1,
		BorderSizePixel = 0, ZIndex = 82, Parent = card,
	}, { corner(10), stroke(1, Color3.fromRGB(70, 70, 90)) })
	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 0, 6),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(160, 160, 180), TextSize = 11,
		Text = "OPPONENT", TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 83, Parent = opponentBox,
	})
	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 8, 0, 22),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 18,
		Text = info.opponent or "?", TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 83, Parent = opponentBox,
	})
	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 0, 44),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(255, 230, 120), TextSize = 13,
		Text = "Elo: " .. tostring(info.opponentElo or 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 83, Parent = opponentBox,
	})

	-- Big circular timer floating top-center.
	local timerLabel = make("TextLabel", {
		Name = "Timer", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.new(0, 70, 0, 70),
		BackgroundColor3 = Color3.fromRGB(28, 28, 42), BackgroundTransparency = 0.1,
		Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 230, 120),
		TextScaled = true, Text = tostring(GameConfig.AbilitySelectDuration),
		ZIndex = 83, Parent = card,
	}, { corner(35), stroke(2, Color3.fromRGB(255, 230, 120)) })

	local grid = make("Frame", {
		Position = UDim2.new(0, 24, 0, 110), Size = UDim2.new(1, -48, 1, -130),
		BackgroundTransparency = 1, ZIndex = 81, Parent = card,
	}, {
		make("UIGridLayout", {
			CellSize = UDim2.new(0, 192, 0, 196),
			CellPadding = UDim2.new(0, 10, 0, 10),
			FillDirectionMaxCells = 6,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	for i, name in ipairs(AbilityDefs.List) do
		local def = AbilityDefs.Display[name]
		local accent = def.color
		local cell = make("Frame", {
			Name = name, LayoutOrder = i,
			BackgroundColor3 = Color3.fromRGB(28, 28, 42), BorderSizePixel = 0,
			ZIndex = 82, Parent = grid,
		}, { corner(12), stroke(2, accent) })

		-- Per-skin tinted gradient gives each card its own glow.
		local cellGrad = Instance.new("UIGradient")
		cellGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, accent:Lerp(Color3.fromRGB(28, 28, 42), 0.65)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(28, 28, 42)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 28, 42)),
		})
		cellGrad.Rotation = 90
		cellGrad.Parent = cell

		-- Color swatch banner at the top of each card.
		make("Frame", {
			Size = UDim2.new(1, -20, 0, 6), Position = UDim2.new(0, 10, 0, 10),
			BackgroundColor3 = accent, BorderSizePixel = 0,
			ZIndex = 83, Parent = cell,
		}, { corner(3) })

		-- Name on its own row, cooldown subtitle directly below — keeps long
		-- ability names ("Super Strength", "Lightning Strike") from clipping
		-- under a side badge.
		local nameLabel = make("TextLabel", {
			Size = UDim2.new(1, -20, 0, 26), Position = UDim2.new(0, 10, 0, 22),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.name, ZIndex = 83, Parent = cell,
		})

		local cdSeconds = def.cooldown or 0
		local cdText = (cdSeconds >= 1)
			and string.format("%ds cooldown", math.floor(cdSeconds))
			or string.format("%.1fs cooldown", cdSeconds)
		make("TextLabel", {
			Name = "Cooldown",
			Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 10, 0, 50),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham,
			TextColor3 = Color3.fromRGB(160, 160, 180), TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = cdText, ZIndex = 83, Parent = cell,
		})

		make("TextLabel", {
			Size = UDim2.new(1, -16, 0, 76), Position = UDim2.new(0, 8, 0, 70),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextWrapped = true,
			TextColor3 = Color3.fromRGB(210, 210, 225), TextSize = 13,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.desc, ZIndex = 83, Parent = cell,
		})

		local btn = make("TextButton", {
			Name = "Pick", AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 32),
			BackgroundColor3 = accent, AutoButtonColor = true, Active = true,
			Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(20, 20, 30),
			TextSize = 14, Text = "Pick", ZIndex = 84, Parent = cell,
		}, { corner(8) })

		btn.MouseButton1Click:Connect(function()
			Remotes.AbilitySelected:FireServer(name)
			nameLabel.TextColor3 = accent
			btn.Text = "Selected"
			btn.AutoButtonColor = false
			btn.Active = false
			task.wait(0.15)
			if selectionGui then selectionGui:Destroy() selectionGui = nil end
		end)

		-- Make the whole cell clickable so users can tap anywhere in the card.
		local fullClick = make("TextButton", {
			AutoButtonColor = false, BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -50), Position = UDim2.new(0, 0, 0, 0),
			Text = "", ZIndex = 83, Parent = cell,
		})
		fullClick.MouseButton1Click:Connect(function()
			btn.MouseButton1Click:Fire()
		end)
	end

	task.spawn(function()
		local remaining = GameConfig.AbilitySelectDuration
		while remaining > 0 and selectionGui and selectionGui.Parent do
			timerLabel.Text = tostring(math.ceil(remaining))
			-- Timer flashes red in the last 3 seconds for urgency.
			if remaining <= 3 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 130, 130)
			end
			task.wait(0.2)
			remaining -= 0.2
		end
		if selectionGui then selectionGui:Destroy() selectionGui = nil end
	end)
end

Remotes.ShowAbilitySelection.OnClientEvent:Connect(openAbilitySelect)

Remotes.MatchCountdown.OnClientEvent:Connect(function(n)
	hud.Countdown.Visible = true
	hud.Countdown.Text = n > 0 and tostring(n) or "FIGHT!"
	if n == 0 then
		task.delay(0.9, function() hud.Countdown.Visible = false end)
	end
end)

local function showBanner(text, color, seconds)
	local banner = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.new(0, 560, 0, 54),
		BackgroundColor3 = Color3.fromRGB(15, 15, 25),
		BackgroundTransparency = 0.2,
		Font = Enum.Font.Gotham,
		TextColor3 = color or Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0,
		TextScaled = true, Text = text, Parent = hud,
	}, { corner(10), stroke(2, color or Color3.fromRGB(255, 255, 255)) })
	task.delay(seconds or 3, function() if banner and banner.Parent then banner:Destroy() end end)
end

Remotes.MatchStarted.OnClientEvent:Connect(function(info)
	state.ability = info.ability
	state.inMatch = true
	state.activeUntil = 0
	state.cooldownUntil = 0
	state.cooldownTotal = 0
	lastSelfHealth = nil
	-- Preload the punch animation asset onto our own character so the first
	-- swing of the match doesn't have to async-download the asset.
	if player.Character then
		task.spawn(function() getPunchTrack(player.Character) end)
	end
	local def = AbilityDefs.Display[info.ability]
	local box = hud.BottomBar.AbilityBox
	box.Visible = true
	hud.BottomBar.Controls.Visible = true
	if def then
		box.BackgroundColor3 = def.color
		box.AbilityName.Text = def.name
		showBanner("YOUR POWER: " .. def.name:upper(), def.color, 4)
	end
	setBar(hud.BottomBar.SelfHealth, 1, "100 / 100")
	setBar(hud.BottomBar.OpponentHealth, 1, "100 / 100")
	hud.BottomBar.SelfHealth.Visible = true
	hud.BottomBar.OpponentHealth.Visible = true
end)

Remotes.MatchEnded.OnClientEvent:Connect(function(info)
	state.inMatch = false
	state.ability = nil
	state.activeUntil = 0
	state.cooldownUntil = 0
	state.cooldownTotal = 0
	lastSelfHealth = nil
	hud.BottomBar.AbilityBox.Visible = false
	hud.BottomBar.Controls.Visible = false
	hud.TopBar.Timer.Text = ""
	-- Health bars stay at their ending value so the post-match result is
	-- legible; they're hidden once the player is back in the lobby below.

	local title = info.draw and "DRAW" or (info.won and "VICTORY" or "DEFEAT")
	local accent = info.draw and Color3.fromRGB(220, 220, 230)
		or (info.won and Color3.fromRGB(120, 240, 150) or Color3.fromRGB(240, 110, 110))

	-- No backdrop, no card. Just stacked text at the top of the screen —
	-- same visual register as the "YOUR POWER" banner at match start, so
	-- the arena stays unobstructed for the kill effect / finishing move
	-- VFX. Layout, top to bottom:
	--   [VICTORY]                       (big, accent, optional)
	--   [Hot streak! +25 Coins]         (medium, only on streak milestone)
	--   [+12 ELO  •  +75 Coins]         (small, combined deltas)
	local delta = info.delta or 0
	local coinReward = info.coins or 0
	local streakTitle = info.streakTitle
	local streakBonus = info.streakBonus or 0

	local eloColor = delta > 0 and Color3.fromRGB(120, 240, 150)
		or (delta < 0 and Color3.fromRGB(240, 110, 110)
			or Color3.fromRGB(220, 220, 220))
	local eloPart
	if delta == 0 then
		eloPart = "0 ELO"
	else
		eloPart = string.format("%s%d ELO", delta >= 0 and "+" or "", delta)
	end
	local deltaText = eloPart
	if coinReward > 0 then
		deltaText = deltaText .. "  •  +" .. tostring(coinReward) .. " Coins"
	end

	local resultLabel = make("TextLabel", {
		Name = "ResultTitle", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80), Size = UDim2.new(0, 520, 0, 80),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
		TextColor3 = accent, TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		TextScaled = true, Text = title, ZIndex = 101, Parent = hud,
	})

	local streakLabel
	if streakTitle then
		local label = streakTitle
		if streakBonus and streakBonus > 0 then
			label = label .. "    +" .. tostring(streakBonus) .. " Coins"
		end
		streakLabel = make("TextLabel", {
			Name = "ResultStreak", AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 168), Size = UDim2.new(0, 360, 0, 28),
			BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
			TextColor3 = Color3.fromRGB(255, 220, 110),
			TextStrokeTransparency = 0,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextSize = 20, Text = label, ZIndex = 101, Parent = hud,
		})
	end

	local deltaY = streakTitle and 200 or 168
	local deltaLabel = make("TextLabel", {
		Name = "ResultDelta", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, deltaY), Size = UDim2.new(0, 380, 0, 30),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
		TextColor3 = eloColor, TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		TextSize = 18, Text = deltaText, ZIndex = 101, Parent = hud,
	})

	task.delay(GameConfig.PostMatchDuration + 0.5, function()
		if resultLabel and resultLabel.Parent then resultLabel:Destroy() end
		if streakLabel and streakLabel.Parent then streakLabel:Destroy() end
		if deltaLabel and deltaLabel.Parent then deltaLabel:Destroy() end
		-- Back in the lobby: hide health bars and the opponent Elo label.
		if hud.BottomBar then
			if hud.BottomBar:FindFirstChild("SelfHealth") then
				hud.BottomBar.SelfHealth.Visible = false
			end
			if hud.BottomBar:FindFirstChild("OpponentHealth") then
				hud.BottomBar.OpponentHealth.Visible = false
			end
		end
	end)
end)

Remotes.DamageNumber.OnClientEvent:Connect(function(character, damage)
	if not character or not character:FindFirstChild("Head") then return end
	local head = character.Head
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 80, 0, 40); bb.AlwaysOnTop = true; bb.Parent = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1; label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.Gotham
	label.TextColor3 = Color3.fromRGB(255, 120, 120)
	label.TextStrokeTransparency = 0; label.TextScaled = true
	label.Text = "-" .. math.floor(damage); label.Parent = bb
	task.spawn(function()
		for i = 1, 20 do
			bb.StudsOffset = Vector3.new(0, 2 + i * 0.1, 0)
			label.TextTransparency = i / 20
			task.wait(0.03)
		end
		bb:Destroy()
	end)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not state.inMatch then return end
	if input.KeyCode == Enum.KeyCode.E then
		local now = os.clock()
		if now < state.cooldownUntil then return end
		local camera = workspace.CurrentCamera
		local aimDir = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
		Remotes.RequestAbilityActivation:FireServer(aimDir)
		local def = AbilityDefs.Display[state.ability]
		local cd = def and def.cooldown or 0
		local active = def and def.activeDuration or 0
		state.activeUntil = now + active
		state.cooldownTotal = cd
		state.cooldownUntil = state.activeUntil + cd
	elseif input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		Remotes.RequestBasicAttack:FireServer()
	end
end)

-- Drive the cooldown overlay: hide completely while the ability is still
-- "active" (e.g. Super Speed burst, decoys still out). Only once the active
-- phase ends do we show the countdown until the ability is ready again.
RunService.RenderStepped:Connect(function()
	local bottom = hud:FindFirstChild("BottomBar")
	local box = bottom and bottom:FindFirstChild("AbilityBox")
	if not box then return end
	local overlay = box:FindFirstChild("CooldownOverlay")
	if not overlay then return end
	local now = os.clock()
	if not state.inMatch or now < state.activeUntil then
		overlay.Visible = false
		return
	end
	local remaining = state.cooldownUntil - now
	if remaining > 0.05 then
		overlay.Visible = true
		local text = overlay:FindFirstChild("CooldownText")
		if text then text.Text = string.format("%.1fs", remaining) end
		local frac = math.clamp(remaining / math.max(0.01, state.cooldownTotal), 0, 1)
		overlay.Size = UDim2.new(1, 0, frac, 0)
		overlay.Position = UDim2.new(0, 0, 1 - frac, 0)
	else
		overlay.Visible = false
	end
end)

-- Hit feedback: flash screen red when the player takes damage (own health drops)
local damageFlash
local function ensureFlash()
	if damageFlash and damageFlash.Parent then return damageFlash end
	damageFlash = make("Frame", {
		Name = "DamageFlash", Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(200, 0, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0,
		ZIndex = 50, Active = false, Parent = hud,
	})
	return damageFlash
end
local function flashRed()
	local f = ensureFlash()
	f.BackgroundTransparency = 0.55
	task.spawn(function()
		for i = 1, 12 do
			f.BackgroundTransparency = 0.55 + i * 0.04
			task.wait(0.025)
		end
		f.BackgroundTransparency = 1
	end)
end

-- Camera shake. Adds a per-frame additive offset to the live camera CFrame
-- and decays back to zero over `duration` seconds. Plays on damage taken
-- AND on landing a punch — both events should feel physical. Decoupled
-- from the red-flash so we can tune them independently.
local _shakeAmount, _shakeDecay = 0, 0
local function addShake(magnitude, duration)
	_shakeAmount = math.max(_shakeAmount, magnitude)
	_shakeDecay = magnitude / math.max(0.05, duration)
end
local _camera = workspace.CurrentCamera
RunService.RenderStepped:Connect(function(dt)
	if _shakeAmount > 0 and _camera then
		local off = Vector3.new(
			(math.random() - 0.5) * _shakeAmount,
			(math.random() - 0.5) * _shakeAmount,
			0
		)
		_camera.CFrame = _camera.CFrame * CFrame.new(off)
		_shakeAmount = math.max(0, _shakeAmount - _shakeDecay * dt)
	end
end)

Remotes.HealthUpdate.OnClientEvent:Connect(function(payload)
	if payload.target == "self" then
		if lastSelfHealth and payload.health < lastSelfHealth - 0.1 then
			flashRed()
			-- Bigger drops shake harder. 30+ damage → big shake, 8 dmg
			-- punches → small shake. Capped so SuperStrength's 30 dmg
			-- crate throws don't spin the camera.
			local drop = lastSelfHealth - payload.health
			local mag = math.clamp(0.25 + drop * 0.025, 0.3, 1.2)
			addShake(mag, 0.35)
		end
		lastSelfHealth = payload.health
	end
end)

-- Visual feedback on ability/attack effects
local function worldSphere(position, color, maxSize, duration)
	duration = duration or 0.35
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false
	p.Shape = Enum.PartType.Ball; p.Material = Enum.Material.Neon
	p.Color = color; p.Size = Vector3.new(1, 1, 1)
	p.Position = position; p.Transparency = 0.1
	p.Parent = workspace
	local TS = game:GetService("TweenService")
	TS:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(maxSize, maxSize, maxSize), Transparency = 1,
	}):Play()
	task.delay(duration + 0.1, function() if p.Parent then p:Destroy() end end)
end

local function showHitMarker()
	local marker = make("TextLabel", {
		Name = "HitMarker", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 80, 0, 80),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(255, 230, 120), TextStrokeTransparency = 0,
		TextScaled = true, Text = "X", ZIndex = 40, Parent = hud,
	})
	task.spawn(function()
		for i = 1, 10 do
			marker.TextTransparency = i / 10
			marker.Size = UDim2.new(0, 80 + i * 6, 0, 80 + i * 6)
			task.wait(0.025)
		end
		marker:Destroy()
	end)
end

-- Punch via real Roblox animation asset. The new R15 rig replaced Motor6Ds
-- with AnimationConstraints (C0/Transform are read-only on those!), so the
-- ONLY way to pose limbs is through the Animator. We use the stock R15
-- Slash (rbxassetid://522635514) - it's an ARM-ONLY overhead-arc animation
-- bundled with sword tools, so legs don't move and it overlays cleanly on
-- top of run/walk movement animations at Action priority.
-- Played at 3× speed so the 0.5s arc condenses into a snappy ~0.17s jab.
local PUNCH_ANIM_ID = "rbxassetid://522635514"
local PUNCH_SPEED = 3.0
local punchTracks = setmetatable({}, { __mode = "k" })  -- character → AnimationTrack

local function findRightHand(character)
	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("RightLowerArm")
		or character:FindFirstChild("RightUpperArm")
end

function getPunchTrack(character)
	local cached = punchTracks[character]
	if cached and cached.Parent then return cached end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = PUNCH_ANIM_ID
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if not ok or not track then return nil end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	punchTracks[character] = track
	return track
end

local function playPunchAnimation(character)
	if not character or not character.Parent then return end
	local track = getPunchTrack(character)
	if not track then return end
	track:Stop(0)
	track:Play(0, 1, PUNCH_SPEED)
end

local function punchStreak(fromPos, toPos, color)
	local dist = (toPos - fromPos).Magnitude
	if dist < 0.1 or dist > 60 then return end
	local streak = Instance.new("Part")
	streak.Anchored = true; streak.CanCollide = false; streak.CanQuery = false
	streak.Material = Enum.Material.Neon
	streak.Color = color or Color3.fromRGB(255, 255, 220)
	streak.Size = Vector3.new(0.6, 0.6, dist)
	streak.CFrame = CFrame.new(fromPos:Lerp(toPos, 0.5), toPos)
	streak.Transparency = 0
	streak.Parent = workspace
	TweenService:Create(streak, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.1, 0.1, dist),
	}):Play()
	task.delay(0.3, function() if streak.Parent then streak:Destroy() end end)
end

local function handBurst(position)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false
	p.Shape = Enum.PartType.Ball; p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 240, 180)
	p.Size = Vector3.new(0.6, 0.6, 0.6)
	p.Position = position; p.Transparency = 0.1
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(0.2), {
		Size = Vector3.new(2.4, 2.4, 2.4),
		Transparency = 1,
	}):Play()
	task.delay(0.25, function() if p.Parent then p:Destroy() end end)
end

local function playPunch(attackerChar, targetChar)
	if not attackerChar then return end
	local hand = findRightHand(attackerChar)
	local hrp = attackerChar:FindFirstChild("HumanoidRootPart")
	if not (hand and hrp) then return end

	local startPos = hand.Position
	local endPos
	if targetChar then
		local tRoot = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Torso")
		if tRoot then endPos = tRoot.Position end
	end
	endPos = endPos or (startPos + hrp.CFrame.LookVector * 4)

	playPunchAnimation(attackerChar)   -- real arm swing via Roblox R15 Slash asset
	handBurst(startPos)
	punchStreak(startPos, endPos)
end

Remotes.AbilityEffect.OnClientEvent:Connect(function(payload)
	if payload.kind == "melee" then
		if payload.from then
			-- Always animate the swing, even on whiffs - the server only sets
			-- payload.to when the hit connected, but the punch itself fires
			-- on every click.
			playPunch(payload.from, payload.to)
		end
		if payload.to then
			local target = payload.to:FindFirstChild("HumanoidRootPart") or payload.to:FindFirstChild("Torso")
			if target then
				worldSphere(target.Position, Color3.fromRGB(255, 230, 120), 3.5, 0.3)
			end
			if payload.from and payload.from == player.Character then
				showHitMarker()
				-- Tiny camera kick on landed hit. Subtle (0.18 mag) so
				-- it reads as feedback, not a screen wobble.
				addShake(0.18, 0.15)
			end
		end
	end
end)

-- Flying client controller: when character has Flying attribute = true,
-- Space/ascend, Shift/descend, WASD steers, camera direction drives movement.
local flyVel
local flyGyro
local flyConn
local function setFlying(on)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end
	if on then
		if flyVel then flyVel:Destroy() end
		if flyGyro then flyGyro:Destroy() end
		flyVel = Instance.new("BodyVelocity")
		flyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		flyVel.Velocity = Vector3.zero
		flyVel.Parent = hrp
		flyGyro = Instance.new("BodyGyro")
		flyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
		flyGyro.D = 500; flyGyro.P = 3000
		flyGyro.CFrame = hrp.CFrame
		flyGyro.Parent = hrp
		hum.PlatformStand = true
		if flyConn then flyConn:Disconnect() end
		flyConn = RunService.RenderStepped:Connect(function()
			if not (char.Parent and hrp.Parent and flyVel and flyVel.Parent) then return end
			local cam = workspace.CurrentCamera
			local dir = Vector3.zero
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
			if dir.Magnitude > 0 then dir = dir.Unit * 45 end

			-- Hard arena bounds: clamp velocity AND position so flying can
			-- never push through walls/ceiling. The arena is centered on
			-- ArenaCenter (set by the server when the match starts) with
			-- inner faces at ±100 horizontally and y=80 vertically. minY
			-- is set above the floor so the character's legs (HRP - 2.5
			-- studs to feet) never sink below the marble.
			local center = char:GetAttribute("ArenaCenter")
			if typeof(center) == "Vector3" then
				local rel = hrp.Position - center
				local margin = 4
				local maxX, maxZ, maxY, minY = 100 - margin, 100 - margin, 80 - margin, 4
				-- Cancel velocity components pushing past a boundary.
				if rel.X >  maxX and dir.X > 0 then dir = Vector3.new(0, dir.Y, dir.Z) end
				if rel.X < -maxX and dir.X < 0 then dir = Vector3.new(0, dir.Y, dir.Z) end
				if rel.Z >  maxZ and dir.Z > 0 then dir = Vector3.new(dir.X, dir.Y, 0) end
				if rel.Z < -maxZ and dir.Z < 0 then dir = Vector3.new(dir.X, dir.Y, 0) end
				if rel.Y >  maxY and dir.Y > 0 then dir = Vector3.new(dir.X, 0, dir.Z) end
				if rel.Y <  minY and dir.Y < 0 then dir = Vector3.new(dir.X, 0, dir.Z) end
				-- Hard position clamp as a last-resort if the player is
				-- already past the boundary (e.g. mid-frame phase-through).
				local clampedRel = Vector3.new(
					math.clamp(rel.X, -maxX, maxX),
					math.clamp(rel.Y, minY, maxY),
					math.clamp(rel.Z, -maxZ, maxZ)
				)
				if (clampedRel - rel).Magnitude > 0.1 then
					hrp.CFrame = CFrame.new(center + clampedRel) * (hrp.CFrame - hrp.Position)
				end
			end

			flyVel.Velocity = dir
			flyGyro.CFrame = CFrame.new(hrp.Position, hrp.Position + cam.CFrame.LookVector)
		end)
	else
		if flyConn then flyConn:Disconnect() flyConn = nil end
		if flyVel then flyVel:Destroy() flyVel = nil end
		if flyGyro then flyGyro:Destroy() flyGyro = nil end
		hum.PlatformStand = false
	end
end

local function hookFlyingAttribute(char)
	char:GetAttributeChangedSignal("Flying"):Connect(function()
		setFlying(char:GetAttribute("Flying") == true)
	end)
	if char:GetAttribute("Flying") then setFlying(true) end
end

if player.Character then hookFlyingAttribute(player.Character) end
player.CharacterAdded:Connect(function(char)
	flyVel, flyGyro, flyConn = nil, nil, nil
	hookFlyingAttribute(char)
end)

-- Show Flying-specific controls hint when the ability is Flying
local baseControlText = "LEFT-CLICK = Attack     •     E = Ability"
local origMatchStarted = Remotes.MatchStarted
origMatchStarted.OnClientEvent:Connect(function(info)
	local bottom = hud:FindFirstChild("BottomBar")
	local controls = bottom and bottom:FindFirstChild("Controls")
	local strip = controls and controls:FindFirstChildOfClass("TextLabel")
	if not strip then return end
	if info.ability == "Flying" then
		strip.Text = "E = Toggle Flight  •  WASD + Space/Shift to move  •  Click = Attack"
	else
		strip.Text = baseControlText
	end
end)

-- ===== Store UI =====
-- Unified shop for skins, kill effects, finishing moves, and Robux→Coins
-- packs. Driven by the OpenStore RemoteEvent (server-fires from lobby
-- ProximityPrompts and from the persistent Store button below).
local OpenStoreEvent = Remotes.OpenStore
local StoreActionRF = Remotes.StoreAction
local storeGui

local CATEGORY_TABS = {
	{ id = "skins",          label = "SKINS" },
	{ id = "killEffects",    label = "KILL EFFECTS" },
	{ id = "finishingMoves", label = "FINISHING MOVES" },
	{ id = "coins",          label = "COINS" },
}

local function closeStore()
	if storeGui and storeGui.Parent then storeGui:Destroy() end
	storeGui = nil
end

local function refreshStore()
	local res = StoreActionRF:InvokeServer({ action = "refresh" })
	return (res and res.state) or nil
end

local function formatCoins(n)
	-- Comma-separate so 12000 reads as "12,000" — small store amounts
	-- look cleaner without separators but pack/coin prices get long.
	n = math.floor(n or 0)
	local s = tostring(n)
	local out, i = "", 0
	for ch in s:reverse():gmatch(".") do
		if i > 0 and i % 3 == 0 then out = "," .. out end
		out = ch .. out
		i += 1
	end
	return out
end

-- Builds a real R15 humanoid model for ViewportFrame previews using the
-- player's own avatar description (so the preview shows their character
-- with the skin on). We anchor every part, strip Animate/scripts/sounds,
-- and snap the model so its center sits at the world origin so PivotTo()
-- can spin it in place inside the viewport.
local cachedDescription
local function getPreviewDescription()
	if cachedDescription then return cachedDescription end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		local ok, desc = pcall(function() return hum:GetAppliedDescription() end)
		if ok and desc then
			cachedDescription = desc
			return desc
		end
	end
	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if ok and desc then
		cachedDescription = desc
		return desc
	end
	return Instance.new("HumanoidDescription")
end

local function buildPreviewRig()
	local desc = getPreviewDescription()
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		local fallback = Instance.new("HumanoidDescription")
		ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(fallback, Enum.HumanoidRigType.R15)
		end)
	end
	if not model then return nil end
	model.Name = "PreviewRig"

	-- CreateHumanoidModelFromDescription returns parts at their asset-load
	-- positions, not the resolved rig pose — the head can come back 13+
	-- studs away from the body. Parking the model in the workspace for one
	-- Heartbeat lets the Humanoid join everything via the rig attachments.
	-- Park it at y=50000 so the brief frame of visibility is well off-screen.
	model:PivotTo(CFrame.new(0, 50000, 0))
	model.Parent = workspace
	RunService.Heartbeat:Wait()
	if not model.Parent then return nil end

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("LuaSourceContainer")
			or child:IsA("Sound")
			or child:IsA("Shirt")
			or child:IsA("Pants")
			or child:IsA("ShirtGraphic")
			or child:IsA("Accessory") then
			child:Destroy()
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Trail")
			or d:IsA("Texture") then
			d:Destroy()
		end
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.Massless = true
		end
	end

	model:PivotTo(CFrame.new(0, 0, 0))
	model.Parent = nil
	return model
end

local function setupSkinViewport(parent, skinName, accent)
	-- Bigger viewport (200 vs 170) gives the character room for full
	-- head-to-feet framing. Strong ambient + bright key light pull the
	-- skin's body color forward instead of drowning it in shadow.
	local viewport = make("ViewportFrame", {
		Name = "Preview",
		Size = UDim2.new(1, -20, 0, 200),
		Position = UDim2.new(0, 10, 0, 10),
		BackgroundColor3 = Color3.fromRGB(40, 40, 55),
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(220, 220, 235),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -0.6, -0.7),
		ZIndex = 94,
		Parent = parent,
	}, { corner(10), stroke(2, accent) })

	-- Backdrop: bright accent halo at the TOP fading to a soft mid tone
	-- at the BOTTOM (no near-black). Adds a vignette feel without
	-- hiding the character's feet.
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, accent:Lerp(Color3.fromRGB(255, 255, 255), 0.40)),
		ColorSequenceKeypoint.new(0.5, accent:Lerp(Color3.fromRGB(60, 60, 84), 0.55)),
		ColorSequenceKeypoint.new(1, accent:Lerp(Color3.fromRGB(48, 48, 70), 0.75)),
	})
	gradient.Rotation = 90
	gradient.Parent = viewport

	-- Pulled the camera back slightly (-10z) and lifted Y to 1.5 so the
	-- character has air above the head and a hint of floor below the feet.
	local cam = Instance.new("Camera")
	cam.FieldOfView = 28
	cam.CFrame = CFrame.lookAt(Vector3.new(2.6, 1.5, -10), Vector3.new(0, -0.4, 0))
	cam.Parent = viewport
	viewport.CurrentCamera = cam

	local rig
	local rotation = 0
	task.spawn(function()
		local built = buildPreviewRig()
		if not built or not viewport.Parent then
			if built then built:Destroy() end
			return
		end
		SkinCatalog.applyPreview(built, skinName)
		built.Parent = viewport
		rig = built
	end)

	local conn = RunService.RenderStepped:Connect(function(dt)
		rotation = rotation + dt * 0.6
		if rig and rig.Parent then
			rig:PivotTo(CFrame.Angles(0, rotation, 0))
		end
	end)
	viewport.AncestryChanged:Connect(function()
		if not viewport:IsDescendantOf(game) then conn:Disconnect() end
	end)

	return viewport
end

local function buildStore(snapshot)
	closeStore()
	if not snapshot then return end

	local backdrop = make("TextButton", {
		Name = "Store", AutoButtonColor = false,
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.4, BorderSizePixel = 0, Text = "",
		ZIndex = 90, Parent = hud,
	})
	storeGui = backdrop
	backdrop.MouseButton1Click:Connect(closeStore)

	local card = make("Frame", {
		Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 1040, 0, 660),
		BackgroundColor3 = Color3.fromRGB(18, 18, 28), BackgroundTransparency = 0.02,
		BorderSizePixel = 0, ZIndex = 91, Parent = backdrop,
	}, { corner(16), stroke(1, Color3.fromRGB(80, 80, 110)) })

	local cardGradient = Instance.new("UIGradient")
	cardGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 30, 50)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(18, 18, 28)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 28)),
	})
	cardGradient.Rotation = 90
	cardGradient.Parent = card

	local cardGuard = make("TextButton", {
		AutoButtonColor = false, Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Text = "", ZIndex = 91, Parent = card,
	})
	cardGuard.MouseButton1Click:Connect(function() end)

	-- Title and subtitle centered horizontally in the modal so the
	-- Roblox topbar's chat/menu icons (top-left CoreGui, can't be
	-- z-ordered below our gui) don't block the words. Both stack
	-- centered as a hero header.
	make("TextLabel", {
		Name = "Title", AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 320, 0, 30), Position = UDim2.new(0.5, 0, 0, 18),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(245, 230, 170),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 22, Text = "Store", ZIndex = 92, Parent = card,
	})
	make("TextLabel", {
		Name = "Subtitle", AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 460, 0, 16), Position = UDim2.new(0.5, 0, 0, 48),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(150, 150, 175),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 12, Text = "Skins, kill effects, finishing moves, and coin packs.",
		ZIndex = 92, Parent = card,
	})

	-- Coin balance pill, top-right next to the close button. Now has a
	-- diamond glyph at the front and uses GothamBold for stronger read.
	local coinPill = make("Frame", {
		Name = "CoinPill", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -68, 0, 22), Size = UDim2.new(0, 170, 0, 36),
		BackgroundColor3 = Color3.fromRGB(28, 30, 46), BorderSizePixel = 0,
		ZIndex = 93, Parent = card,
	}, { corner(10), stroke(1, Color3.fromRGB(255, 220, 110)) })
	make("TextLabel", {
		Name = "CoinIcon", Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(0, 22, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 220, 120),
		TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16,
		Text = "◆", ZIndex = 93, Parent = coinPill,
	})
	local coinLabel = make("TextLabel", {
		Position = UDim2.new(0, 36, 0, 0),
		Size = UDim2.new(1, -46, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 230, 130),
		TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14,
		Text = formatCoins(snapshot.coins),
		ZIndex = 93, Parent = coinPill,
	})

	local closeBtn = make("TextButton", {
		Name = "Close", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 24), Size = UDim2.new(0, 32, 0, 32),
		BackgroundColor3 = Color3.fromRGB(28, 28, 42), AutoButtonColor = true,
		Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(220, 220, 230),
		TextSize = 18, Text = "✕", ZIndex = 93, Parent = card,
	}, { corner(8), stroke(1, Color3.fromRGB(80, 80, 110)) })
	closeBtn.MouseButton1Click:Connect(closeStore)

	-- Thin divider under the header to visually separate it from the tab strip.
	make("Frame", {
		Position = UDim2.new(0, 24, 0, 72), Size = UDim2.new(1, -48, 0, 1),
		BackgroundColor3 = Color3.fromRGB(60, 60, 80), BorderSizePixel = 0,
		ZIndex = 92, Parent = card,
	})

	local tabBar = make("Frame", {
		Position = UDim2.new(0, 24, 0, 84), Size = UDim2.new(1, -48, 0, 40),
		BackgroundTransparency = 1, ZIndex = 92, Parent = card,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local content = make("Frame", {
		Name = "Content", Position = UDim2.new(0, 24, 0, 140),
		Size = UDim2.new(1, -48, 1, -184), BackgroundTransparency = 1,
		ZIndex = 91, Parent = card,
	})

	local status = make("TextLabel", {
		Name = "Status", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -300, 0, 22),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(180, 180, 200), TextSize = 13,
		Text = "", ZIndex = 92, Parent = card,
	})

	local activeTab = "skins"
	local current = snapshot

	local tabButtons = {}
	local renderTab

	-- Tab style: same medium-weight font and same neutral text color in
	-- both states. Active state is shown by a thin yellow underline + a
	-- slightly lighter background, NOT by switching to bold (the previous
	-- bold-on-select made the strip look noisy).
	local function setActive(tabId)
		activeTab = tabId
		for id, btn in pairs(tabButtons) do
			local on = id == tabId
			btn.BackgroundColor3 = on and Color3.fromRGB(36, 36, 52) or Color3.fromRGB(24, 24, 38)
			btn.TextColor3 = on and Color3.fromRGB(255, 235, 160) or Color3.fromRGB(170, 170, 190)
			local underline = btn:FindFirstChild("Underline")
			if underline then underline.Visible = on end
		end
		renderTab()
	end

	for i, tab in ipairs(CATEGORY_TABS) do
		local btn = make("TextButton", {
			Name = "Tab_" .. tab.id, LayoutOrder = i,
			Size = UDim2.new(0, 184, 1, 0),
			BackgroundColor3 = Color3.fromRGB(24, 24, 38), AutoButtonColor = false,
			Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(170, 170, 190),
			TextSize = 13, Text = tab.label, ZIndex = 92, Parent = tabBar,
		}, { corner(6) })
		make("Frame", {
			Name = "Underline", AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(0, 60, 0, 2),
			BackgroundColor3 = Color3.fromRGB(255, 220, 110), BorderSizePixel = 0,
			Visible = false, ZIndex = 93, Parent = btn,
		}, { corner(2) })
		tabButtons[tab.id] = btn
		btn.MouseButton1Click:Connect(function() setActive(tab.id) end)
	end

	local function clearContent()
		for _, c in ipairs(content:GetChildren()) do c:Destroy() end
	end

	-- Generic grid container. Skins use a tall 4-per-row layout (with a
	-- 3D viewport on top of each card); cosmetics use a shorter 5-per-row
	-- layout (no preview, just a tinted accent strip + text). Coin packs
	-- have their own grid in renderCoins.
	local function makeGridHolder(cellSize, perRow, padding)
		return make("Frame", {
			Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
			ZIndex = 91, Parent = content,
		}, {
			make("UIGridLayout", {
				CellSize = cellSize,
				CellPadding = UDim2.new(0, padding or 8, 0, 12),
				FillDirectionMaxCells = perRow,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end

	local function invoke(payload, statusText)
		status.Text = statusText or "Processing..."
		local res = StoreActionRF:InvokeServer(payload)
		if res and res.state then
			current = res.state
			coinLabel.Text = formatCoins(current.coins)
			renderTab()
		end
		if res and res.reason == "prompted" then
			status.Text = "Check the Robux purchase prompt."
		elseif res and res.reason == "insufficient-coins" then
			status.Text = "Not enough coins."
		elseif res and res.ok then
			status.Text = "Done."
		else
			status.Text = "Could not complete."
		end
	end

	-- Action button factories. Both styles share the same medium-weight
	-- font + thin border so the cosmetic cards don't shout. The Coins
	-- button is filled when affordable, hollow + dim when not.
	local function makeActionButton(parent, bottomOffset, props)
		return make("TextButton", {
			Size = UDim2.new(1, -16, 0, 32), Position = UDim2.new(0, 8, 1, bottomOffset),
			Font = Enum.Font.GothamMedium, AutoButtonColor = props.active ~= false,
			Active = props.active ~= false,
			BackgroundColor3 = props.bg, TextColor3 = props.fg,
			TextSize = 13, Text = props.text, ZIndex = 94, Parent = parent,
		}, { corner(6) })
	end

	local function attachActionButtons(cell, item, category)
		if item.equipped then
			makeActionButton(cell, -40, {
				bg = Color3.fromRGB(36, 36, 52),
				fg = Color3.fromRGB(150, 230, 175),
				text = "Equipped", active = false,
			})
		elseif item.owned then
			local btn = makeActionButton(cell, -40, {
				bg = Color3.fromRGB(255, 220, 110),
				fg = Color3.fromRGB(28, 28, 38),
				text = "Equip",
			})
			btn.MouseButton1Click:Connect(function()
				invoke({ action = "equip", category = category, item = item.name }, "Equipping...")
			end)
		else
			local robuxBtn = makeActionButton(cell, -76, {
				bg = Color3.fromRGB(80, 170, 90),
				fg = Color3.fromRGB(255, 255, 255),
				text = "R$  " .. tostring(item.robuxPrice or 0),
			})
			robuxBtn.MouseButton1Click:Connect(function()
				invoke({ action = "buy", category = category, item = item.name, payWith = "robux" }, "Processing...")
			end)

			local coinAfford = (current.coins or 0) >= (item.coinPrice or 0)
			local coinBtn = makeActionButton(cell, -40, {
				bg = coinAfford and Color3.fromRGB(36, 36, 52) or Color3.fromRGB(28, 28, 38),
				fg = coinAfford and Color3.fromRGB(255, 220, 110) or Color3.fromRGB(110, 110, 130),
				text = formatCoins(item.coinPrice or 0) .. "  Coins",
				active = coinAfford,
			})
			-- Thin yellow outline on the coin button to brand it without
			-- making the whole card shout in yellow.
			make("UIStroke", {
				Thickness = 1,
				Color = coinAfford and Color3.fromRGB(255, 220, 110) or Color3.fromRGB(70, 70, 90),
				Parent = coinBtn,
			})
			if coinAfford then
				coinBtn.MouseButton1Click:Connect(function()
					invoke({ action = "buy", category = category, item = item.name, payWith = "coins" }, "Processing...")
				end)
			end
		end
	end

	-- Tall card with rotating 3D character preview (skins).
	local function buildSkinCell(grid, i, item)
		local accent = item.accentColor or Color3.fromRGB(200, 200, 200)
		local cell = make("Frame", {
			Name = item.name, LayoutOrder = i,
			BackgroundColor3 = Color3.fromRGB(24, 24, 36), BorderSizePixel = 0,
			ZIndex = 92, Parent = grid,
		}, { corner(10), stroke(1, Color3.fromRGB(60, 60, 80)) })

		setupSkinViewport(cell, item.name, accent)

		-- Status badge in the top-right corner of the viewport area.
		-- "EQUIPPED" pops in green, "OWNED" in yellow, locked items get
		-- nothing (the price IS the status).
		if item.equipped then
			local badge = make("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 16), Size = UDim2.new(0, 86, 0, 22),
				BackgroundColor3 = Color3.fromRGB(34, 130, 70), BorderSizePixel = 0,
				ZIndex = 95, Parent = cell,
			}, { corner(6) })
			make("TextLabel", {
				Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(220, 255, 230),
				TextSize = 11, Text = "EQUIPPED", ZIndex = 96, Parent = badge,
			})
		elseif item.owned then
			local badge = make("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 16), Size = UDim2.new(0, 70, 0, 22),
				BackgroundColor3 = Color3.fromRGB(180, 140, 50), BorderSizePixel = 0,
				ZIndex = 95, Parent = cell,
			}, { corner(6) })
			make("TextLabel", {
				Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 245, 220),
				TextSize = 11, Text = "OWNED", ZIndex = 96, Parent = badge,
			})
		end

		make("TextLabel", {
			Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 8, 0, 216),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(245, 245, 250), TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = item.displayName or item.name, ZIndex = 94, Parent = cell,
		})

		make("TextLabel", {
			Size = UDim2.new(1, -16, 0, 50), Position = UDim2.new(0, 8, 0, 240),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextWrapped = true,
			TextColor3 = Color3.fromRGB(180, 180, 200), TextSize = 11,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = item.description or "", ZIndex = 94, Parent = cell,
		})

		attachActionButtons(cell, item, "skins")
	end

	-- Compact card without a 3D preview (kill effects + finishing moves).
	-- Just an accent stripe across the top, name, description, then buttons.
	local function buildCosmeticCell(grid, i, item, category)
		local accent = item.accentColor or Color3.fromRGB(200, 200, 200)
		local cell = make("Frame", {
			Name = item.name, LayoutOrder = i,
			BackgroundColor3 = Color3.fromRGB(24, 24, 36), BorderSizePixel = 0,
			ZIndex = 92, Parent = grid,
		}, { corner(10), stroke(1, Color3.fromRGB(60, 60, 80)) })

		make("Frame", {
			Name = "Accent", Size = UDim2.new(1, 0, 0, 4),
			BackgroundColor3 = accent, BorderSizePixel = 0,
			ZIndex = 94, Parent = cell,
		}, { corner(2) })

		make("TextLabel", {
			Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 8, 0, 18),
			BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
			TextColor3 = Color3.fromRGB(245, 245, 250), TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = item.displayName or item.name, ZIndex = 94, Parent = cell,
		})

		local statusText, statusColor
		if item.equipped then statusText, statusColor = "Equipped", Color3.fromRGB(150, 230, 175)
		elseif item.owned then statusText, statusColor = "Owned", Color3.fromRGB(255, 220, 110)
		else statusText, statusColor = "Locked", Color3.fromRGB(150, 170, 200) end
		make("TextLabel", {
			Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 8, 0, 42),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham,
			TextColor3 = statusColor, TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = statusText, ZIndex = 94, Parent = cell,
		})

		make("TextLabel", {
			Size = UDim2.new(1, -16, 0, 110), Position = UDim2.new(0, 8, 0, 64),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextWrapped = true,
			TextColor3 = Color3.fromRGB(170, 170, 190), TextSize = 11,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = item.description or "", ZIndex = 94, Parent = cell,
		})

		attachActionButtons(cell, item, category)
	end

	local function renderSkins()
		-- Skins live inside a ScrollingFrame because there are now 6+ of
		-- them and a 2-row grid no longer fits the content area. The card
		-- height was tightened from 460 → 340 to remove the dead space
		-- between the description and the action buttons.
		local scroller = make("ScrollingFrame", {
			Name = "SkinScroll", Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 6, ScrollBarImageColor3 = Color3.fromRGB(120, 120, 150),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ZIndex = 91, Parent = content,
		})
		-- Cell size 224x376: viewport is 200 (was 170), title at y=216,
		-- description y=240..290, action buttons at y=300/336.
		local grid = make("Frame", {
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, ZIndex = 91, Parent = scroller,
		}, {
			make("UIGridLayout", {
				CellSize = UDim2.new(0, 224, 0, 376),
				CellPadding = UDim2.new(0, 12, 0, 12),
				FillDirectionMaxCells = 4,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local data = current.skins or { items = {} }
		for i, item in ipairs(data.items) do
			buildSkinCell(grid, i, item)
		end
	end

	local function renderCosmetics(category)
		-- 5 × 192 + 4 × 8 = 992; matches the 992-wide content area
		-- (1040 modal − 48 horizontal padding) so all five fit on one row.
		local grid = makeGridHolder(UDim2.new(0, 192, 0, 220), 5, 8)
		local data = current[category] or { items = {} }
		for i, item in ipairs(data.items) do
			buildCosmeticCell(grid, i, item, category)
		end
	end

	local function renderCoins()
		local holder = make("Frame", {
			Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
			ZIndex = 91, Parent = content,
		}, {
			make("UIGridLayout", {
				CellSize = UDim2.new(0, 224, 0, 240),
				CellPadding = UDim2.new(0, 12, 0, 12),
				FillDirectionMaxCells = 4,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local packs = current.coinPacks or {}
		local titleCase = function(s) return s:sub(1, 1):upper() .. s:sub(2) end
		for i, pack in ipairs(packs) do
			local cell = make("Frame", {
				Name = pack.key, LayoutOrder = i,
				BackgroundColor3 = Color3.fromRGB(24, 24, 36), BorderSizePixel = 0,
				ZIndex = 92, Parent = holder,
			}, { corner(10), stroke(1, Color3.fromRGB(60, 60, 80)) })

			make("Frame", {
				Name = "Accent", Size = UDim2.new(1, 0, 0, 4),
				BackgroundColor3 = Color3.fromRGB(255, 220, 110), BorderSizePixel = 0,
				ZIndex = 94, Parent = cell,
			}, { corner(2) })

			make("TextLabel", {
				Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 20),
				BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
				TextColor3 = Color3.fromRGB(245, 245, 250), TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = titleCase(pack.key), ZIndex = 94, Parent = cell,
			})
			make("TextLabel", {
				Name = "Coins", Size = UDim2.new(1, -20, 0, 50),
				Position = UDim2.new(0, 10, 0, 64),
				BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
				TextColor3 = Color3.fromRGB(255, 220, 110), TextSize = 36,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = formatCoins(pack.coins), ZIndex = 94, Parent = cell,
			})
			make("TextLabel", {
				Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 10, 0, 116),
				BackgroundTransparency = 1, Font = Enum.Font.Gotham,
				TextColor3 = Color3.fromRGB(170, 170, 190), TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "Coins", ZIndex = 94, Parent = cell,
			})

			local btn = make("TextButton", {
				Size = UDim2.new(1, -20, 0, 36), Position = UDim2.new(0, 10, 1, -48),
				BackgroundColor3 = Color3.fromRGB(80, 170, 90), AutoButtonColor = true,
				Active = true, Font = Enum.Font.GothamMedium,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 14, Text = "R$  " .. tostring(pack.robux),
				ZIndex = 94, Parent = cell,
			}, { corner(6) })
			btn.MouseButton1Click:Connect(function()
				invoke({ action = "buy", category = "coins", item = pack.key }, "Processing...")
			end)
		end
	end

	function renderTab()
		clearContent()
		if activeTab == "skins" then renderSkins()
		elseif activeTab == "killEffects" then renderCosmetics("killEffects")
		elseif activeTab == "finishingMoves" then renderCosmetics("finishingMoves")
		elseif activeTab == "coins" then renderCoins() end
	end

	-- Auto-refresh on grants from ProcessReceipt. The server publishes
	-- ownership and equip changes via player attributes (one per category)
	-- so we can listen without polling.
	local connections = {}
	local function autoRefresh()
		if not storeGui or not storeGui.Parent then return end
		local snap = refreshStore()
		if snap then
			current = snap
			coinLabel.Text = formatCoins(current.coins)
			renderTab()
			status.Text = "Updated."
		end
	end
	for _, attr in ipairs({
		"OwnedSkins", "EquippedSkin",
		"OwnedKillEffects", "EquippedKillEffect",
		"OwnedFinishingMoves", "EquippedFinishingMove",
		"Coins",
	}) do
		table.insert(connections, player:GetAttributeChangedSignal(attr):Connect(autoRefresh))
	end
	-- Capture a local reference: closeStore() sets the upvalue `storeGui` to
	-- nil before the AncestryChanged callback fires on Destroy, so reading
	-- the upvalue here would index nil.
	local thisGui = backdrop
	thisGui.AncestryChanged:Connect(function()
		if not thisGui:IsDescendantOf(game) then
			for _, c in ipairs(connections) do c:Disconnect() end
		end
	end)

	setActive("skins")
end

OpenStoreEvent.OnClientEvent:Connect(function(snap)
	if snap and snap.inMatch then return end
	buildStore(snap)
end)

-- Bottom-left lobby cluster: Store button on top of the coin balance chip.
-- Both share the rank/leaderboard panels' navy + yellow-accent treatment
-- so the lobby HUD reads as one cohesive design system.
-- Single right-side column (rank → leaderboard btn → store → coins).
-- Y positions are: rank panel ends at 214, lbButton 222–264, store
-- 272–314, coins 322–354. Width 300 matches the rank panel above.
local storeButton = make("TextButton", {
	Name = "StoreButton", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 272), Size = UDim2.new(0, 300, 0, 42),
	BackgroundColor3 = Color3.fromRGB(46, 48, 72), AutoButtonColor = true,
	Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(245, 245, 250),
	TextSize = 15, Text = "Store", ZIndex = 20, Parent = hud,
}, { corner(10), stroke(1, Color3.fromRGB(90, 90, 120)) })
storeButton.MouseButton1Click:Connect(function()
	if state.inMatch then return end
	local snap = refreshStore()
	if snap then buildStore(snap) end
end)

-- Coins chip sits directly under the Store button as the bottom row of
-- the right-side column. Same width (300) so the column reads as one.
local coinsChip = make("Frame", {
	Name = "CoinsChip", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 322), Size = UDim2.new(0, 300, 0, 32),
	BackgroundColor3 = Color3.fromRGB(20, 22, 36), BackgroundTransparency = 0.05,
	BorderSizePixel = 0, ZIndex = 20, Parent = hud,
}, { corner(10), stroke(1, Color3.fromRGB(70, 70, 95)) })

-- Wrap the icon + value in a centered horizontal layout so the cluster
-- is centered as a unit no matter the digit count.
local coinInner = make("Frame", {
	Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0),
	BackgroundTransparency = 1, ZIndex = 21, Parent = coinsChip,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
make("TextLabel", {
	Name = "CoinIcon", LayoutOrder = 1,
	Size = UDim2.new(0, 16, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
	TextColor3 = Color3.fromRGB(255, 220, 110), TextSize = 14,
	Text = "◆", ZIndex = 22, Parent = coinInner,
})
local coinsLabel = make("TextLabel", {
	Name = "CoinsLabel", LayoutOrder = 2,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 1, 1, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(255, 220, 110),
	TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14,
	Text = "0", ZIndex = 22, Parent = coinInner,
})

local function updateCoinsChip()
	coinsLabel.Text = formatCoins(player:GetAttribute("Coins") or 0) .. " Coins"
end
updateCoinsChip()
player:GetAttributeChangedSignal("Coins"):Connect(updateCoinsChip)

-- ----- Lobby Rank+Stats panel (top-right) ------------------------------------
-- Stacks above the Top Players button on the right side of the screen so
-- the lobby HUD reads as one cluster on the right and the bottom-left
-- carries the store + coins. Three rows: tier line + Elo, progress bar to
-- the next tier, stats row (W / L / Win-Rate / Streak / Best).
local rankPanel = make("Frame", {
	Name = "RankPanel", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 58), Size = UDim2.new(0, 300, 0, 156),
	BackgroundColor3 = Color3.fromRGB(20, 22, 36), BackgroundTransparency = 0.05,
	BorderSizePixel = 0, ZIndex = 18, Parent = hud,
}, { corner(12), stroke(1, Color3.fromRGB(70, 70, 95)) })

-- Subtle vertical gradient: dark navy → slightly lighter at top so the
-- panel reads as raised instead of flat. Same trick the picker cards use.
local rankGradient = Instance.new("UIGradient")
rankGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 36, 56)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 22, 36)),
})
rankGradient.Rotation = 90
rankGradient.Parent = rankPanel

local rankTierLbl = make("TextLabel", {
	Name = "Tier", AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 14, 0, 12), Size = UDim2.new(1, -120, 0, 28),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(220, 150, 90),
	TextXAlignment = Enum.TextXAlignment.Left, TextSize = 20,
	Text = "Bronze", ZIndex = 19, Parent = rankPanel,
})
local rankEloLbl = make("TextLabel", {
	Name = "Elo", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 14), Size = UDim2.new(0, 110, 0, 24),
	BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
	TextColor3 = Color3.fromRGB(200, 200, 225),
	TextXAlignment = Enum.TextXAlignment.Right, TextSize = 14,
	Text = "Elo 0", ZIndex = 19, Parent = rankPanel,
})

-- Progress bar.
local progressBg = make("Frame", {
	Name = "ProgressBg", Position = UDim2.new(0, 14, 0, 50),
	Size = UDim2.new(1, -28, 0, 8), BackgroundColor3 = Color3.fromRGB(36, 38, 58),
	BorderSizePixel = 0, ZIndex = 19, Parent = rankPanel,
}, { corner(4) })
local progressFill = make("Frame", {
	Name = "Fill", Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(220, 150, 90), BorderSizePixel = 0,
	ZIndex = 20, Parent = progressBg,
}, { corner(4) })
local progressTextLbl = make("TextLabel", {
	Name = "ProgressText", Position = UDim2.new(0, 14, 0, 60),
	Size = UDim2.new(1, -28, 0, 14), BackgroundTransparency = 1,
	Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(150, 150, 175),
	TextXAlignment = Enum.TextXAlignment.Left, TextSize = 11,
	Text = "Progress to next tier", ZIndex = 19, Parent = rankPanel,
})

-- Divider line between progress bar and stats row.
make("Frame", {
	Position = UDim2.new(0, 14, 0, 84), Size = UDim2.new(1, -28, 0, 1),
	BackgroundColor3 = Color3.fromRGB(60, 62, 86), BorderSizePixel = 0,
	BackgroundTransparency = 0.4, ZIndex = 19, Parent = rankPanel,
})

-- Stats strip. Five evenly-spaced columns. Numbers are 22pt and prominent;
-- labels underneath are 9pt, all-caps, dim — quickly scannable.
local STATS_Y = 92
local STATS_W = 272 -- panel width (300) - 14*2 padding
local STATS_X0 = 14
local function statColumn(idx, label, color, valueText)
	local x = STATS_X0 + math.floor((idx - 1) * STATS_W / 5)
	local w = math.floor(STATS_W / 5)
	local col = make("Frame", {
		Position = UDim2.new(0, x, 0, STATS_Y),
		Size = UDim2.new(0, w, 0, 50), BackgroundTransparency = 1,
		ZIndex = 19, Parent = rankPanel,
	})
	local v = make("TextLabel", {
		Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextColor3 = color, TextSize = 22, Text = valueText or "0",
		ZIndex = 19, Parent = col,
	})
	make("TextLabel", {
		Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(140, 140, 165),
		TextSize = 9, Text = label,
		ZIndex = 19, Parent = col,
	})
	return v
end
local winsValLbl   = statColumn(1, "WINS",   Color3.fromRGB(120, 235, 150))
local lossesValLbl = statColumn(2, "LOSSES", Color3.fromRGB(235, 120, 120))
local winrateLbl   = statColumn(3, "WIN %",  Color3.fromRGB(230, 230, 250))
local streakLbl    = statColumn(4, "STREAK", Color3.fromRGB(255, 200, 110))
local bestLbl      = statColumn(5, "BEST",   Color3.fromRGB(255, 220, 150))

local function refreshRankPanel()
	local elo = player:GetAttribute("Elo") or GameConfig.DefaultElo
	local wins = player:GetAttribute("Wins") or 0
	local losses = player:GetAttribute("Losses") or 0
	local streakN = player:GetAttribute("Streak") or 0
	local bestN = player:GetAttribute("BestStreak") or 0
	local pct, tier, nextTier = Ranks.progress(elo)

	rankTierLbl.Text = tier.name
	rankTierLbl.TextColor3 = tier.accent
	rankEloLbl.Text = "Elo " .. tostring(elo)
	progressFill.Size = UDim2.new(pct, 0, 1, 0)
	progressFill.BackgroundColor3 = tier.accent
	if nextTier then
		progressTextLbl.Text = string.format(
			"%d / %d to %s",
			math.max(0, elo - tier.min),
			nextTier.min - tier.min,
			nextTier.name
		)
	else
		progressTextLbl.Text = "MAX RANK — Grandmaster"
	end

	winsValLbl.Text = tostring(wins)
	lossesValLbl.Text = tostring(losses)
	local total = wins + losses
	winrateLbl.Text = total > 0
		and tostring(math.floor(100 * wins / total + 0.5)) .. "%"
		or "—"
	streakLbl.Text = tostring(streakN)
	bestLbl.Text = tostring(bestN)
end

for _, attr in ipairs({ "Elo", "Wins", "Losses", "Streak", "BestStreak" }) do
	player:GetAttributeChangedSignal(attr):Connect(refreshRankPanel)
end
refreshRankPanel()

-- Bonus toast (welcome + daily). Stacks vertically when multiple fire
-- back-to-back (a fresh player on day-1 receives both within one frame).
-- Each toast slides in from the right, holds 3s, then fades and dies.
local nextToastSlot = 0
Remotes.BonusGranted.OnClientEvent:Connect(function(payload)
	if not payload or type(payload) ~= "table" then return end
	local label = payload.kind == "welcome" and "Welcome bonus"
		or (payload.kind == "daily" and "Daily reward" or "Bonus")
	local slot = nextToastSlot
	nextToastSlot += 1
	local toast = make("Frame", {
		Name = "BonusToast", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 40, 0, 80 + slot * 56),
		Size = UDim2.new(0, 240, 0, 48),
		BackgroundColor3 = Color3.fromRGB(24, 24, 36),
		BackgroundTransparency = 0.05, BorderSizePixel = 0,
		ZIndex = 60, Parent = hud,
	}, { corner(8), stroke(1, Color3.fromRGB(255, 220, 110)) })
	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 0, 6),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(180, 180, 200), TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left, Text = label,
		ZIndex = 61, Parent = toast,
	})
	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 8, 0, 22),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
		TextColor3 = Color3.fromRGB(255, 220, 110), TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "+" .. tostring(payload.amount or 0) .. " Coins",
		ZIndex = 61, Parent = toast,
	})
	TweenService:Create(toast,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(1, -16, 0, 80 + slot * 56) }):Play()
	task.delay(3, function()
		if not toast.Parent then return end
		TweenService:Create(toast,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(1, 40, 0, 80 + slot * 56),
			  BackgroundTransparency = 1 }):Play()
		task.wait(0.5)
		toast:Destroy()
		nextToastSlot = math.max(0, nextToastSlot - 1)
	end)
end)

-- ----- Top-10 server leaderboard ---------------------------------------------
-- Hidden by default; open via the trophy button (lobby only) or TAB key
-- on PC. Re-fetches each open so the snapshot is fresh — the data set is
-- tiny (max 10 rows) so the round-trip is negligible.
-- Leaderboard panel docks to the right edge so it never blocks the center
-- of the screen. Same dark-navy + yellow-accent treatment as the rank
-- panel below it for visual cohesion.
-- Panel docks to the LEFT of the right-side column (column right edge
-- is at x=screen-16, column width 300, +8px gap, so panel right edge
-- at x=screen-16-300-8 = screen-324). Vertical aligns with the rank
-- panel's top so the two read as siblings.
local lbPanel = make("Frame", {
	Name = "Leaderboard", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -324, 0, 58), Size = UDim2.new(0, 320, 0, 360),
	BackgroundColor3 = Color3.fromRGB(20, 22, 36), BackgroundTransparency = 0.05,
	BorderSizePixel = 0, Visible = false, ZIndex = 90, Parent = hud,
}, { corner(12), stroke(1, Color3.fromRGB(70, 70, 95)) })

local lbGradient = Instance.new("UIGradient")
lbGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 36, 56)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 22, 36)),
})
lbGradient.Rotation = 90
lbGradient.Parent = lbPanel

make("TextLabel", {
	Name = "LBTitle", Position = UDim2.new(0, 16, 0, 14),
	Size = UDim2.new(1, -56, 0, 26), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(245, 230, 170),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 16, Text = "Top Players", ZIndex = 91, Parent = lbPanel,
})
make("TextLabel", {
	Name = "LBSubtitle", Position = UDim2.new(0, 16, 0, 38),
	Size = UDim2.new(1, -56, 0, 16), BackgroundTransparency = 1,
	Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(150, 150, 175),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 11, Text = "Live ranking on this server",
	ZIndex = 91, Parent = lbPanel,
})

local lbCloseBtn = make("TextButton", {
	Name = "LBClose", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12), Size = UDim2.new(0, 32, 0, 32),
	BackgroundColor3 = Color3.fromRGB(40, 42, 60), Text = "✕",
	Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(220, 220, 240),
	TextSize = 16, ZIndex = 92, Parent = lbPanel,
}, { corner(8) })

-- Header row pinned just above the list so column meanings are visible
-- without taking a row from the list.
local lbHeader = make("Frame", {
	Name = "LBHeader", Position = UDim2.new(0, 12, 0, 64),
	Size = UDim2.new(1, -24, 0, 22), BackgroundTransparency = 1,
	ZIndex = 91, Parent = lbPanel,
})
make("TextLabel", {
	Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(0, 28, 1, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(140, 140, 165),
	TextXAlignment = Enum.TextXAlignment.Left, TextSize = 10,
	Text = "#", ZIndex = 92, Parent = lbHeader,
})
make("TextLabel", {
	Position = UDim2.new(0, 44, 0, 0), Size = UDim2.new(1, -180, 1, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(140, 140, 165),
	TextXAlignment = Enum.TextXAlignment.Left, TextSize = 10,
	Text = "PLAYER", ZIndex = 92, Parent = lbHeader,
})
make("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -68, 0, 0), Size = UDim2.new(0, 70, 1, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(140, 140, 165),
	TextXAlignment = Enum.TextXAlignment.Right, TextSize = 10,
	Text = "TIER", ZIndex = 92, Parent = lbHeader,
})
make("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0, 50, 1, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(140, 140, 165),
	TextXAlignment = Enum.TextXAlignment.Right, TextSize = 10,
	Text = "ELO", ZIndex = 92, Parent = lbHeader,
})

local lbList = make("Frame", {
	Name = "LBList", Position = UDim2.new(0, 12, 0, 88),
	Size = UDim2.new(1, -24, 1, -100), BackgroundTransparency = 1,
	ZIndex = 91, Parent = lbPanel,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}),
})
local lbLayout = make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
})
lbLayout.Parent = lbList

local function refreshLeaderboard()
	-- Clear existing rows.
	for _, child in ipairs(lbList:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
	end
	local ok, list = pcall(function() return Remotes.GetTopPlayers:InvokeServer() end)
	if not ok or type(list) ~= "table" or #list == 0 then
		local empty = make("Frame", {
			Position = UDim2.new(0, 0, 0, 80),
			Size = UDim2.new(1, 0, 0, 80), BackgroundTransparency = 1,
			ZIndex = 91, Parent = lbList,
		})
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(220, 220, 240),
			TextSize = 16, Text = "Be the first to climb",
			ZIndex = 91, Parent = empty,
		})
		make("TextLabel", {
			Position = UDim2.new(0, 0, 0, 32),
			Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1,
			Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(150, 150, 175),
			TextSize = 11, Text = "Step on a duel pad to start ranking up.",
			ZIndex = 91, Parent = empty,
		})
		return
	end
	for i, e in ipairs(list) do
		local tier = Ranks.fromElo(e.elo)
		local rankColor =
			(i == 1) and Color3.fromRGB(255, 215, 60)
			or (i == 2) and Color3.fromRGB(220, 220, 220)
			or (i == 3) and Color3.fromRGB(220, 150, 90)
			or Color3.fromRGB(160, 160, 180)
		local row = make("Frame", {
			Name = "LBRow_" .. i, Size = UDim2.new(1, 0, 0, 32),
			-- Top 3 get a faint accent gradient stripe along the left edge;
			-- everyone else uses a flat dark fill so the eye finds the
			-- podium positions without scanning numbers.
			BackgroundColor3 = (i <= 3) and Color3.fromRGB(40, 42, 64) or Color3.fromRGB(26, 28, 44),
			BorderSizePixel = 0, LayoutOrder = i, ZIndex = 91, Parent = lbList,
		}, { corner(6) })
		if i <= 3 then
			make("Frame", {
				Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(0, 3, 1, 0),
				BackgroundColor3 = rankColor, BorderSizePixel = 0,
				ZIndex = 92, Parent = row,
			})
		end
		make("TextLabel", {
			Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(0, 32, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
			TextColor3 = rankColor,
			TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14,
			Text = "#" .. i, ZIndex = 92, Parent = row,
		})
		make("TextLabel", {
			Position = UDim2.new(0, 44, 0, 0), Size = UDim2.new(1, -180, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(245, 245, 250),
			TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14,
			Text = e.name, TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 92, Parent = row,
		})
		make("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -68, 0, 0), Size = UDim2.new(0, 70, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextColor3 = tier.accent,
			TextXAlignment = Enum.TextXAlignment.Right, TextSize = 11,
			Text = string.upper(tier.name), ZIndex = 92, Parent = row,
		})
		make("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0, 50, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(220, 220, 240),
			TextXAlignment = Enum.TextXAlignment.Right, TextSize = 14,
			Text = tostring(e.elo), ZIndex = 92, Parent = row,
		})
	end
end

local function toggleLeaderboard(forceVisible)
	local target = forceVisible
	if target == nil then target = not lbPanel.Visible end
	if target and not lbPanel.Visible then refreshLeaderboard() end
	lbPanel.Visible = target
end
lbCloseBtn.MouseButton1Click:Connect(function() toggleLeaderboard(false) end)

-- Leaderboard button: docked to the top-right corner so it lives next to
-- the panel it opens. Compact size + trophy glyph keeps it readable on
-- mobile without crowding the lobby.
-- Same flat treatment as the Store button. No emoji (renders
-- unreliably across platforms) and no yellow tint (caused glow).
local lbButton = make("TextButton", {
	Name = "LBButton", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 222), Size = UDim2.new(0, 300, 0, 42),
	BackgroundColor3 = Color3.fromRGB(46, 48, 72), AutoButtonColor = true,
	Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(245, 245, 250),
	TextSize = 14, Text = "Top Players", ZIndex = 18, Parent = hud,
}, { corner(10), stroke(1, Color3.fromRGB(90, 90, 120)) })
lbButton.MouseButton1Click:Connect(function()
	if state.inMatch then return end
	toggleLeaderboard()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		if state.inMatch then return end
		toggleLeaderboard()
	end
end)

-- Single source of truth for lobby HUD visibility. Defined AFTER all lobby
-- elements (rankPanel, lbButton, lbPanel, storeButton, coinsChip) so the
-- function's upvalues resolve to the right local variables. (When this
-- helper sat above the leaderboard panel definitions, lbButton resolved
-- to a global = nil, the assignment errored, and the leaderboard button
-- stayed visible during fights.)
local function setLobbyHudVisible(visible)
	storeButton.Visible = visible
	coinsChip.Visible = visible
	rankPanel.Visible = visible
	lbButton.Visible = visible
	if not visible then
		lbPanel.Visible = false
	end
end

Remotes.ShowAbilitySelection.OnClientEvent:Connect(function()
	setLobbyHudVisible(false)
	closeStore()
end)
Remotes.MatchStarted.OnClientEvent:Connect(function()
	setLobbyHudVisible(false)
	closeStore()
end)
Remotes.MatchEnded.OnClientEvent:Connect(function()
	task.delay(GameConfig.PostMatchDuration + 0.5, function()
		setLobbyHudVisible(true)
	end)
end)

-- Server-wide notifications. Today's only sender is the streak milestone
-- broadcast; the banner is intentionally generic so other event types
-- (rank-ups, "GG", hot-spots) can reuse the same surface later.
local activeBroadcastSlot = 0
Remotes.BroadcastNotification.OnClientEvent:Connect(function(payload)
	if not payload or type(payload) ~= "table" then return end
	local slot = activeBroadcastSlot
	activeBroadcastSlot += 1

	local headline = "Notification"
	local subtitle = ""
	local accent = Color3.fromRGB(255, 230, 120)
	if payload.kind == "streak" then
		headline = string.format("🔥 %s — %d-WIN STREAK!",
			payload.playerName or "Someone", payload.count or 0)
		subtitle = payload.title or ""
		accent = Color3.fromRGB(255, 160, 80)
	else
		headline = payload.headline or headline
		subtitle = payload.subtitle or subtitle
		accent = payload.accent or accent
	end

	local banner = make("Frame", {
		Name = "BroadcastBanner", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -90),
		Size = UDim2.new(0, 480, 0, 70),
		BackgroundColor3 = Color3.fromRGB(20, 22, 36),
		BackgroundTransparency = 0.05, BorderSizePixel = 0,
		ZIndex = 80, Parent = hud,
	}, { corner(10), stroke(2, accent) })
	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 32), Position = UDim2.new(0, 8, 0, 6),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
		TextColor3 = accent, TextSize = 22, TextScaled = false,
		TextXAlignment = Enum.TextXAlignment.Center, Text = headline,
		ZIndex = 81, Parent = banner,
	})
	if subtitle ~= "" then
		make("TextLabel", {
			Size = UDim2.new(1, -16, 0, 24), Position = UDim2.new(0, 8, 0, 38),
			BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
			TextColor3 = Color3.fromRGB(220, 220, 240), TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Center, Text = subtitle,
			ZIndex = 81, Parent = banner,
		})
	end

	-- Drop in, hold, retract.
	TweenService:Create(banner,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 80 + slot * 84) }):Play()
	task.delay(3.5, function()
		if not banner.Parent then return end
		TweenService:Create(banner,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 0, -90),
			  BackgroundTransparency = 1 }):Play()
		task.wait(0.5)
		banner:Destroy()
		activeBroadcastSlot = math.max(0, activeBroadcastSlot - 1)
	end)
end)
