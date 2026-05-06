local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config  = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Ranks   = require(Shared:WaitForChild("Ranks"))

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

-- Display info: friendly names, colors, descriptions, and cooldowns (mirror server).
local DISPLAY = {
	Flying        = { name = "Aerial Ace",   color = Color3.fromRGB(120, 200, 255), desc = "Hover. Press E for an upward burst.",                           cd = 0.6 },
	Teleportation = { name = "Blink",        color = Color3.fromRGB(200, 120, 255), desc = "Press E to blink 30 studs forward.",                            cd = 4   },
	SuperStrength = { name = "Super Strength", color = Color3.fromRGB(255, 120, 80), desc = "Punches deal 3x damage. E for a ground-slam shockwave.",        cd = 6   },
	SuperSpeed    = { name = "Super Speed",  color = Color3.fromRGB(255, 230, 100), desc = "Always 2x walkspeed. E for a 2s sprint burst.",                  cd = 6   },
	Invisibility  = { name = "Invisibility", color = Color3.fromRGB(180, 180, 200), desc = "1.5x punch dmg. E to vanish for 4s.",                            cd = 10  },
	Fire          = { name = "Pyromancer",   color = Color3.fromRGB(255, 130, 60),  desc = "E hurls a fireball — 25 dmg + 3s burn.",                         cd = 4   },
	Ice           = { name = "Cryomancer",   color = Color3.fromRGB(140, 220, 255), desc = "E launches a freeze shard — 15 dmg + 1.5s freeze.",              cd = 7   },
	Lightning     = { name = "Stormcaller",  color = Color3.fromRGB(255, 240, 120), desc = "E snaps an instant lightning bolt — 30 dmg, 50-stud range.",     cd = 4   },
	Telekinesis   = { name = "Telekinetic",  color = Color3.fromRGB(170, 100, 220), desc = "E lifts your foe, then slams them down — 25 dmg.",               cd = 7   },
	Shadow        = { name = "Shadowstrike", color = Color3.fromRGB(80,  60, 130),  desc = "E dashes 30 studs, briefly invuln, 25 dmg through.",             cd = 5   },
}

-- ScreenGui ------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "SuperpowerShowdownUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = pg

-- Helpers --------------------------------------------------------------------

local function makeFrame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props or {}) do f[k] = v end
	f.Parent = parent
	return f
end
local function makeLabel(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0
	for k, v in pairs(props or {}) do l[k] = v end
	l.Parent = parent
	return l
end
local function makeButton(parent, props)
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	for k, v in pairs(props or {}) do b[k] = v end
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = b
	return b
end
local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = inst
	return c
end
local function stroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(120, 130, 160)
	s.Thickness = thickness or 1.5
	s.Transparency = transparency or 0.4
	s.Parent = inst
	return s
end
local function gradient(inst, c1, c2, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(c1, c2)
	g.Rotation = rotation or 90
	g.Parent = inst
	return g
end

-- Welcome overlay ------------------------------------------------------------

local welcome = makeFrame(gui, {
	Name = "Welcome",
	Size = UDim2.fromScale(0.55, 0.55),
	Position = UDim2.fromScale(0.225, 0.22),
	BackgroundColor3 = Color3.fromRGB(20, 24, 40),
	BackgroundTransparency = 0.05,
})
corner(welcome, 18)
stroke(welcome, Color3.fromRGB(255, 230, 120), 2, 0.2)
gradient(welcome, Color3.fromRGB(28, 32, 56), Color3.fromRGB(14, 14, 24), 90)

makeLabel(welcome, {
	Size = UDim2.new(1, -20, 0, 80),
	Position = UDim2.fromOffset(10, 16),
	Text = "⚔ SUPERPOWER SHOWDOWN ⚔",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = Color3.fromRGB(255, 230, 120),
})
makeLabel(welcome, {
	Size = UDim2.new(1, -40, 0, 30),
	Position = UDim2.fromOffset(20, 100),
	Text = "Ranked 1v1 Duels — Climb the Ladder, Earn Your Tier",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(220, 220, 250),
})
makeLabel(welcome, {
	Size = UDim2.new(1, -40, 0, 100),
	Position = UDim2.fromOffset(20, 145),
	Text = "1.  Stand on a glowing pad (blue or red) for 3 seconds to queue.\n2.  Pick from 10 powers in the 8-second selector.\n3.  60-second fight to 0 HP — winner climbs, loser drops.\n4.  Bronze → Silver → Gold → Platinum → Diamond → Master → Grandmaster.",
	TextWrapped = true,
	TextScaled = true,
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(220, 220, 240),
})
makeLabel(welcome, {
	Size = UDim2.new(1, -40, 0, 36),
	Position = UDim2.new(0, 20, 1, -110),
	Text = "Controls:  LEFT-CLICK = Attack    •    E = Power    •    TAB = Leaderboard",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(120, 220, 255),
})
local closeBtn = makeButton(welcome, {
	Size = UDim2.fromOffset(160, 44),
	Position = UDim2.new(0.5, -80, 1, -64),
	Text = "Let's Duel",
	BackgroundColor3 = Color3.fromRGB(60, 200, 120),
})
gradient(closeBtn, Color3.fromRGB(80, 220, 130), Color3.fromRGB(40, 170, 100), 90)
closeBtn.MouseButton1Click:Connect(function() welcome.Visible = false end)

-- Persistent controls strip --------------------------------------------------

local controlsStrip = makeFrame(gui, {
	Name = "Controls",
	Size = UDim2.new(0, 420, 0, 36),
	Position = UDim2.new(0.5, -210, 1, -50),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.4,
})
corner(controlsStrip, 10)
makeLabel(controlsStrip, {
	Size = UDim2.fromScale(1, 1),
	Text = "LEFT-CLICK = Attack    •    E = Power    •    TAB = Leaderboard",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(220, 220, 240),
})

-- Lobby rank panel (top-left) ------------------------------------------------

local rankPanel = makeFrame(gui, {
	Name = "RankPanel",
	Size = UDim2.fromOffset(260, 100),
	Position = UDim2.fromOffset(16, 16),
	BackgroundColor3 = Color3.fromRGB(20, 24, 40),
	BackgroundTransparency = 0.15,
})
corner(rankPanel, 12)
stroke(rankPanel, Color3.fromRGB(255, 230, 120), 1.5, 0.4)
local rankBigLbl = makeLabel(rankPanel, {
	Size = UDim2.new(1, -16, 0, 36),
	Position = UDim2.fromOffset(8, 6),
	Text = "Bronze",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(220, 150, 90),
})
local rankEloLbl = makeLabel(rankPanel, {
	Size = UDim2.new(1, -16, 0, 22),
	Position = UDim2.fromOffset(8, 40),
	Text = "Elo: 1000",
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(220, 220, 240),
})
local progressBg = makeFrame(rankPanel, {
	Size = UDim2.new(1, -16, 0, 10),
	Position = UDim2.new(0, 8, 1, -28),
	BackgroundColor3 = Color3.fromRGB(40, 40, 60),
})
corner(progressBg, 5)
local progressFill = makeFrame(progressBg, {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(255, 230, 120),
})
corner(progressFill, 5)
local progressLbl = makeLabel(rankPanel, {
	Size = UDim2.new(1, -16, 0, 14),
	Position = UDim2.new(0, 8, 1, -14),
	Text = "Progress to next tier",
	TextScaled = true,
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(180, 180, 200),
})

-- Lobby stats panel ----------------------------------------------------------

local statsPanel = makeFrame(gui, {
	Name = "StatsPanel",
	Size = UDim2.fromOffset(260, 100),
	Position = UDim2.fromOffset(16, 124),
	BackgroundColor3 = Color3.fromRGB(20, 24, 40),
	BackgroundTransparency = 0.15,
})
corner(statsPanel, 12)
stroke(statsPanel, Color3.fromRGB(120, 220, 255), 1.5, 0.4)
makeLabel(statsPanel, {
	Size = UDim2.new(1, -16, 0, 22),
	Position = UDim2.fromOffset(8, 6),
	Text = "Career",
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(220, 220, 240),
})
local winsLbl = makeLabel(statsPanel, {
	Size = UDim2.new(0.5, -8, 0, 22),
	Position = UDim2.fromOffset(8, 32),
	Text = "Wins: 0",
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(120, 220, 130),
})
local lossesLbl = makeLabel(statsPanel, {
	Size = UDim2.new(0.5, -8, 0, 22),
	Position = UDim2.new(0.5, 0, 0, 32),
	Text = "Losses: 0",
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(220, 130, 130),
})
local winRateLbl = makeLabel(statsPanel, {
	Size = UDim2.new(0.5, -8, 0, 22),
	Position = UDim2.fromOffset(8, 56),
	Text = "Win rate: —",
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(220, 220, 240),
})
local streakLbl = makeLabel(statsPanel, {
	Size = UDim2.new(0.5, -8, 0, 22),
	Position = UDim2.new(0.5, 0, 0, 56),
	Text = "Streak: 0",
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(255, 220, 120),
})
local bestStreakLbl = makeLabel(statsPanel, {
	Size = UDim2.new(1, -16, 0, 18),
	Position = UDim2.new(0, 8, 1, -22),
	Text = "Best streak: 0",
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(180, 180, 200),
})

-- Leaderboard panel (toggle with Tab) ----------------------------------------

local leaderboard = makeFrame(gui, {
	Name = "Leaderboard",
	Size = UDim2.fromOffset(360, 420),
	Position = UDim2.new(1, -376, 0, 16),
	BackgroundColor3 = Color3.fromRGB(20, 24, 40),
	BackgroundTransparency = 0.1,
	Visible = false,
})
corner(leaderboard, 12)
stroke(leaderboard, Color3.fromRGB(255, 230, 120), 1.5, 0.3)
makeLabel(leaderboard, {
	Size = UDim2.new(1, -16, 0, 32),
	Position = UDim2.fromOffset(8, 8),
	Text = "🏆  TOP 10",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = Color3.fromRGB(255, 230, 120),
})
local lbList = makeFrame(leaderboard, {
	Size = UDim2.new(1, -16, 1, -52),
	Position = UDim2.fromOffset(8, 44),
	BackgroundTransparency = 1,
})
local lbLayout = Instance.new("UIListLayout")
lbLayout.FillDirection = Enum.FillDirection.Vertical
lbLayout.SortOrder = Enum.SortOrder.LayoutOrder
lbLayout.Padding = UDim.new(0, 4)
lbLayout.Parent = lbList

local function refreshLeaderboard()
	for _, c in ipairs(lbList:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local ok, list = pcall(function() return Remotes.GetTopPlayers:InvokeServer() end)
	if not ok or type(list) ~= "table" then return end
	for i, e in ipairs(list) do
		local row = makeFrame(lbList, {
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundColor3 = (i <= 3) and Color3.fromRGB(50, 56, 90) or Color3.fromRGB(30, 34, 56),
			LayoutOrder = i,
		})
		corner(row, 6)
		makeLabel(row, {
			Size = UDim2.fromOffset(34, 32),
			Text = "#" .. i,
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = (i == 1) and Color3.fromRGB(255, 215,  60)
				or (i == 2) and Color3.fromRGB(220, 220, 220)
				or (i == 3) and Color3.fromRGB(220, 150,  90)
				or Color3.fromRGB(160, 160, 180),
		})
		makeLabel(row, {
			Size = UDim2.new(1, -120, 1, 0),
			Position = UDim2.fromOffset(40, 0),
			Text = e.name,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(220, 220, 240),
		})
		local tier = Ranks.fromElo(e.elo)
		makeLabel(row, {
			Size = UDim2.fromOffset(80, 32),
			Position = UDim2.new(1, -80, 0, 0),
			Text = tostring(e.elo),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = tier.accent,
		})
	end
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		leaderboard.Visible = not leaderboard.Visible
		if leaderboard.Visible then refreshLeaderboard() end
	end
end)

-- Ability HUD (during fight) -------------------------------------------------

local abilityHud = makeFrame(gui, {
	Name = "AbilityHUD",
	Size = UDim2.new(0, 300, 0, 110),
	Position = UDim2.new(1, -320, 1, -180),
	BackgroundColor3 = Color3.fromRGB(20, 24, 40),
	BackgroundTransparency = 0.1,
	Visible = false,
})
corner(abilityHud, 12)
stroke(abilityHud, Color3.fromRGB(120, 130, 160), 1.5, 0.4)
local abilityNameLbl = makeLabel(abilityHud, {
	Size = UDim2.new(1, -20, 0, 36),
	Position = UDim2.fromOffset(10, 6),
	Text = "Power",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextXAlignment = Enum.TextXAlignment.Left,
})
local abilityKeyLbl = makeLabel(abilityHud, {
	Size = UDim2.new(1, -20, 0, 26),
	Position = UDim2.fromOffset(10, 44),
	Text = "Press E to use",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 230, 120),
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
})
local cooldownBar = makeFrame(abilityHud, {
	Size = UDim2.new(1, -20, 0, 10),
	Position = UDim2.new(0, 10, 1, -22),
	BackgroundColor3 = Color3.fromRGB(50, 50, 70),
})
corner(cooldownBar, 5)
local cooldownFill = makeFrame(cooldownBar, {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(120, 220, 255),
})
corner(cooldownFill, 5)

-- HP bar ---------------------------------------------------------------------

local hpFrame = makeFrame(gui, {
	Name = "HP",
	Size = UDim2.new(0, 460, 0, 38),
	Position = UDim2.new(0.5, -230, 0, 18),
	BackgroundColor3 = Color3.fromRGB(20, 24, 40),
	Visible = false,
})
corner(hpFrame, 8)
stroke(hpFrame, Color3.fromRGB(120, 130, 160), 1.5, 0.5)
local hpFill = makeFrame(hpFrame, {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(220, 80, 80),
})
corner(hpFill, 8)
gradient(hpFill, Color3.fromRGB(255, 110, 110), Color3.fromRGB(180, 50, 50), 90)
local hpLabel = makeLabel(hpFrame, {
	Size = UDim2.fromScale(1, 1),
	Text = "100 / 100",
	TextScaled = true,
})

-- Match timer ----------------------------------------------------------------

local timerLbl = makeLabel(gui, {
	Name = "Timer",
	Size = UDim2.new(0, 120, 0, 56),
	Position = UDim2.new(0.5, -60, 0, 60),
	Text = "",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = Color3.fromRGB(255, 230, 120),
	Visible = false,
})

-- Banner ---------------------------------------------------------------------

local banner = makeLabel(gui, {
	Name = "Banner",
	Size = UDim2.new(1, 0, 0, 110),
	Position = UDim2.fromScale(0, 0.32),
	Text = "",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = Color3.fromRGB(255, 230, 120),
	Visible = false,
})

local function showBanner(text, color, seconds)
	banner.Text = text
	banner.TextColor3 = color or Color3.fromRGB(255, 230, 120)
	banner.Visible = true
	banner.TextTransparency = 1
	banner.TextStrokeTransparency = 1
	-- Pop-in
	local fadeIn = TweenService:Create(banner, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0,
	})
	fadeIn:Play()
	task.delay(seconds or 2.5, function()
		if banner.Text ~= text then return end
		local fadeOut = TweenService:Create(banner, TweenInfo.new(0.4), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		fadeOut:Play()
		fadeOut.Completed:Wait()
		if banner.Text == text then banner.Visible = false end
	end)
end

-- Ability picker (2-row grid for 10 abilities) -------------------------------

local picker = makeFrame(gui, {
	Name = "Picker",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.35,
	Visible = false,
})
local pickerTitle = makeLabel(picker, {
	Size = UDim2.new(1, 0, 0, 80),
	Position = UDim2.fromOffset(0, 28),
	Text = "CHOOSE YOUR POWER",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = Color3.fromRGB(255, 230, 120),
})
local pickerSubtitle = makeLabel(picker, {
	Size = UDim2.new(1, 0, 0, 30),
	Position = UDim2.fromOffset(0, 110),
	Text = "Click an ability — auto-picks if you wait too long",
	TextScaled = true,
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(220, 220, 240),
})
local pickerTimer = makeLabel(picker, {
	Size = UDim2.new(1, 0, 0, 30),
	Position = UDim2.fromOffset(0, 142),
	Text = "",
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(255, 200, 200),
})

-- Fixed 5×2 grid (locked width so layout doesn't reshuffle on different screen sizes).
local pickerGrid = makeFrame(picker, {
	Name = "Grid",
	Size = UDim2.fromOffset(956, 414),
	Position = UDim2.new(0.5, -478, 0.5, -120),
	BackgroundTransparency = 1,
})
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(180, 200)
gridLayout.CellPadding = UDim2.fromOffset(14, 14)
gridLayout.FillDirectionMaxCells = 5
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = pickerGrid

local pickerButtons = {}
local pickedName = nil

for idx, abilityName in ipairs(Config.ABILITIES) do
	local d = DISPLAY[abilityName]
	local btn = makeButton(pickerGrid, {
		BackgroundColor3 = d.color,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = idx,
	})
	gradient(btn, d.color, Color3.new(d.color.R * 0.65, d.color.G * 0.65, d.color.B * 0.65), 90)
	stroke(btn, Color3.fromRGB(255, 255, 255), 2, 0.6)
	makeLabel(btn, {
		Size = UDim2.new(1, -10, 0, 50),
		Position = UDim2.fromOffset(5, 8),
		Text = d.name,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(20, 20, 30),
		TextStrokeTransparency = 1,
	})
	makeLabel(btn, {
		Size = UDim2.new(1, -16, 1, -98),
		Position = UDim2.fromOffset(8, 60),
		Text = d.desc,
		TextScaled = true,
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(20, 20, 30),
		TextStrokeTransparency = 1,
	})
	makeLabel(btn, {
		Size = UDim2.new(1, -10, 0, 24),
		Position = UDim2.new(0, 5, 1, -28),
		Text = string.format("⏱  %.1fs CD", d.cd),
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(20, 20, 30),
		TextStrokeTransparency = 1,
	})
	btn.MouseButton1Click:Connect(function()
		if pickedName then return end
		pickedName = abilityName
		Remotes.AbilityChosen:FireServer(abilityName)
		btn.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
		pickerSubtitle.Text = "Locked in: " .. d.name
	end)
	pickerButtons[abilityName] = btn
end

-- Camera shake ---------------------------------------------------------------

local shakeAmt = 0
local shakeDecay = 0
local function addShake(magnitude, duration)
	shakeAmt = math.max(shakeAmt, magnitude)
	shakeDecay = magnitude / math.max(0.05, duration)
end
RunService.RenderStepped:Connect(function(dt)
	if shakeAmt > 0 then
		local off = Vector3.new((math.random()-0.5)*shakeAmt, (math.random()-0.5)*shakeAmt, 0)
		camera.CFrame = camera.CFrame * CFrame.new(off)
		shakeAmt = math.max(0, shakeAmt - shakeDecay * dt)
	end
end)

-- Screen flash ---------------------------------------------------------------

local flash = makeFrame(gui, {
	Name = "Flash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(220, 60, 60),
	BackgroundTransparency = 1,
	ZIndex = 50,
})
local function doFlash(color)
	flash.BackgroundColor3 = color or Color3.fromRGB(220, 60, 60)
	flash.BackgroundTransparency = 0.55
	TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end

-- Damage number renderer (world-space billboard) -----------------------------

local function spawnDamageNumber(pos, amount)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = pos
	part.Parent = Workspace
	Debris:AddItem(part, 1.4)

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 60)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = part

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "-" .. tostring(amount)
	lbl.TextColor3 = Color3.fromRGB(255, 220, 120)
	lbl.TextStrokeTransparency = 0
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.Parent = bb

	-- Float up and fade
	local rise = TweenService:Create(part, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = pos + Vector3.new(0, 6, 0),
	})
	local fade = TweenService:Create(lbl, TweenInfo.new(1.0), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	rise:Play() fade:Play()
end

-- VFX rendering --------------------------------------------------------------

local function tempPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props or {}) do p[k] = v end
	p.Parent = Workspace
	return p
end

local function vfx_punch(data)
	-- Quick beam between attacker and target.
	local mid = (data.from + data.to) / 2
	local dist = (data.to - data.from).Magnitude
	local ring = tempPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.5, 2.5, 2.5),
		Color = Color3.fromRGB(255, 240, 200),
		Position = data.to,
		Transparency = 0.2,
	})
	Debris:AddItem(ring, 0.45)
	TweenService:Create(ring, TweenInfo.new(0.45), {
		Size = Vector3.new(6, 6, 6),
		Transparency = 1,
	}):Play()
end

local function vfx_slam(data)
	local ring = tempPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 1, 1),
		Color = Color3.fromRGB(255, 140, 60),
		Position = data.pos,
		CFrame = CFrame.new(data.pos) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 0.15,
	})
	Debris:AddItem(ring, 0.7)
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.5, data.radius * 2.4, data.radius * 2.4),
		Transparency = 1,
	}):Play()

	-- Burst sphere
	local sphere = tempPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		Color = Color3.fromRGB(255, 200, 100),
		Position = data.pos + Vector3.new(0, 1, 0),
		Transparency = 0.1,
	})
	Debris:AddItem(sphere, 0.5)
	TweenService:Create(sphere, TweenInfo.new(0.5), {
		Size = Vector3.new(data.radius, data.radius, data.radius),
		Transparency = 1,
	}):Play()
end

local function vfx_blink(data)
	for _, pos in ipairs({ data.from, data.to }) do
		local p = tempPart({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2, 2, 2),
			Color = Color3.fromRGB(200, 120, 255),
			Position = pos,
			Transparency = 0.2,
		})
		Debris:AddItem(p, 0.5)
		TweenService:Create(p, TweenInfo.new(0.5), {
			Size = Vector3.new(8, 8, 8),
			Transparency = 1,
		}):Play()
	end
end

local function vfx_sprintBurst(data)
	-- Small ring at feet
	local p = tempPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 4, 4),
		CFrame = CFrame.new(data.pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 230, 100),
		Transparency = 0.2,
	})
	Debris:AddItem(p, 0.4)
	TweenService:Create(p, TweenInfo.new(0.4), {
		Size = Vector3.new(0.4, 10, 10),
		Transparency = 1,
	}):Play()
end

local function vfx_vanish(data)
	local p = tempPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		Color = Color3.fromRGB(150, 150, 200),
		Position = data.pos,
		Transparency = 0.4,
	})
	Debris:AddItem(p, 0.6)
	TweenService:Create(p, TweenInfo.new(0.6), {
		Size = Vector3.new(8, 8, 8),
		Transparency = 1,
	}):Play()
end

local function vfx_flap(data)
	local p = tempPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 3, 3),
		CFrame = CFrame.new(data.pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(180, 220, 255),
		Transparency = 0.3,
	})
	Debris:AddItem(p, 0.4)
	TweenService:Create(p, TweenInfo.new(0.4), {
		Size = Vector3.new(0.4, 9, 9),
		Transparency = 1,
	}):Play()
end

-- Generic projectile renderer (fireball + iceShard share this).
local function vfx_projectile(kind, data)
	local color = (kind == "fireball") and Color3.fromRGB(255, 130, 60) or Color3.fromRGB(140, 220, 255)
	local proj = tempPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.5, 2.5, 2.5),
		Color = color,
		Position = data.origin,
		Transparency = 0.05,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 4
	light.Range = 12
	light.Parent = proj
	Debris:AddItem(proj, data.lifetime + 0.2)

	-- Trail via attachments
	local atta = Instance.new("Attachment")
	atta.Position = Vector3.new(0, 0, 0.5)
	atta.Parent = proj
	local attb = Instance.new("Attachment")
	attb.Position = Vector3.new(0, 0, -0.5)
	attb.Parent = proj
	local trail = Instance.new("Trail")
	trail.Attachment0 = atta
	trail.Attachment1 = attb
	trail.Color = ColorSequence.new(color, color)
	trail.Lifetime = 0.4
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.LightEmission = 1
	trail.Parent = proj

	-- Move it
	task.spawn(function()
		local elapsed = 0
		local stepHz = 60
		local dt = 1 / stepHz
		while elapsed < data.lifetime and proj.Parent do
			task.wait(dt)
			elapsed += dt
			proj.Position = data.origin + data.direction * data.speed * elapsed
		end
	end)
end

local function vfx_lightning(data)
	-- Jagged segments between from and to.
	local from, to = data.from, data.to
	local total = (to - from).Magnitude
	local segments = 8
	for i = 1, segments do
		local t1 = (i - 1) / segments
		local t2 = i / segments
		local p1 = from:Lerp(to, t1)
		local p2 = from:Lerp(to, t2)
		-- Add some jitter perpendicular to the line
		local along = (to - from).Unit
		local jitter = Vector3.new(math.random()-0.5, math.random()-0.5, math.random()-0.5) * 4
		p2 = p2 + jitter - along * jitter:Dot(along)
		local mid = (p1 + p2) / 2
		local seg = tempPart({
			Size = Vector3.new(0.4, 0.4, (p2 - p1).Magnitude),
			CFrame = CFrame.lookAt(mid, p2),
			Color = Color3.fromRGB(255, 240, 200),
			Transparency = 0.1,
		})
		Debris:AddItem(seg, 0.35)
		TweenService:Create(seg, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	end
	-- Impact flash
	local flash_ = tempPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4, 4, 4),
		Position = to,
		Color = Color3.fromRGB(255, 255, 200),
		Transparency = 0.05,
	})
	Debris:AddItem(flash_, 0.4)
	TweenService:Create(flash_, TweenInfo.new(0.4), { Size = Vector3.new(10, 10, 10), Transparency = 1 }):Play()
end

local function vfx_freeze(data)
	-- Ice shards puff at target.
	for _ = 1, 6 do
		local s = tempPart({
			Size = Vector3.new(0.6, 1.2, 0.6),
			Color = Color3.fromRGB(180, 230, 255),
			Position = data.pos + Vector3.new((math.random()-0.5)*4, math.random()*3, (math.random()-0.5)*4),
			Transparency = 0.1,
		})
		Debris:AddItem(s, data.duration)
		TweenService:Create(s, TweenInfo.new(data.duration), { Transparency = 1 }):Play()
	end
end

local function vfx_burn(data)
	-- Fire emitter on the target's position; it stays for the duration.
	local p = tempPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		Color = Color3.fromRGB(255, 100, 60),
		Position = data.pos + Vector3.new(0, 2, 0),
		Transparency = 0.5,
	})
	Debris:AddItem(p, data.duration)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/fire_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(220, 90, 30))
	pe.Size = NumberSequence.new(2, 0.5)
	pe.Transparency = NumberSequence.new(0.2, 1)
	pe.Lifetime = NumberRange.new(0.8)
	pe.Rate = 60
	pe.Speed = NumberRange.new(2, 5)
	pe.SpreadAngle = Vector2.new(20, 20)
	pe.LightEmission = 1
	pe.Parent = p
end

local function vfx_lift(data)
	-- Spiral of small parts orbiting the lift point briefly.
	for i = 1, 8 do
		task.delay(i * 0.05, function()
			local s = tempPart({
				Size = Vector3.new(0.6, 0.6, 0.6),
				Color = Color3.fromRGB(170, 100, 220),
				Position = data.pos + Vector3.new(math.cos(i)*4, i, math.sin(i)*4),
				Transparency = 0.2,
			})
			Debris:AddItem(s, data.duration)
			TweenService:Create(s, TweenInfo.new(data.duration), { Transparency = 1 }):Play()
		end)
	end
end

local function vfx_shadowDash(data)
	-- A trail of dark spheres along the path.
	local dist = (data.to - data.from).Magnitude
	local steps = 10
	for i = 0, steps do
		task.delay(i * 0.02, function()
			local pos = data.from:Lerp(data.to, i / steps)
			local s = tempPart({
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(2.5, 2.5, 2.5),
				Position = pos + Vector3.new(0, 1, 0),
				Color = Color3.fromRGB(100, 70, 160),
				Transparency = 0.2,
			})
			Debris:AddItem(s, 0.5)
			TweenService:Create(s, TweenInfo.new(0.5), {
				Size = Vector3.new(0.2, 0.2, 0.2),
				Transparency = 1,
			}):Play()
		end)
	end
end

local function vfx_ko(data)
	-- Big ring + screen banner.
	local ring = tempPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 2, 2),
		CFrame = CFrame.new(data.pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 60, 60),
		Transparency = 0.1,
	})
	Debris:AddItem(ring, 0.8)
	TweenService:Create(ring, TweenInfo.new(0.8), {
		Size = Vector3.new(0.5, 30, 30),
		Transparency = 1,
	}):Play()
	showBanner("K.O.", Color3.fromRGB(255, 80, 80), 1.6)
end

local effectHandlers = {
	punch        = vfx_punch,
	slam         = vfx_slam,
	blink        = vfx_blink,
	sprintBurst  = vfx_sprintBurst,
	vanish       = vfx_vanish,
	flap         = vfx_flap,
	fireball     = function(d) vfx_projectile("fireball", d) end,
	iceShard     = function(d) vfx_projectile("iceShard", d) end,
	lightning    = vfx_lightning,
	freeze       = vfx_freeze,
	burn         = vfx_burn,
	lift         = vfx_lift,
	shadowDash   = vfx_shadowDash,
	ko           = vfx_ko,
	damageNumber = function(d) spawnDamageNumber(d.pos, d.amount) end,
}

Remotes.Effect.OnClientEvent:Connect(function(kind, data)
	local handler = effectHandlers[kind]
	if handler then handler(data) end
end)

-- Hit feedback (per-client; only fired to the involved players) --------------

Remotes.HitFeedback.OnClientEvent:Connect(function(kind, data)
	if kind == "hurt" then
		addShake(0.6, 0.25)
		doFlash(Color3.fromRGB(220, 60, 60))
	elseif kind == "hit" then
		addShake(0.2, 0.15)
		-- Tiny crosshair "+N" in the center
		local pop = makeLabel(gui, {
			Size = UDim2.fromOffset(120, 40),
			Position = UDim2.new(0.5, -60, 0.5, 30),
			Text = "+" .. tostring(math.floor(data.amount + 0.5)),
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.fromRGB(255, 230, 120),
		})
		Debris:AddItem(pop, 0.7)
		TweenService:Create(pop, TweenInfo.new(0.7), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			Position = UDim2.new(0.5, -60, 0.5, -10),
		}):Play()
	end
end)

-- Input ----------------------------------------------------------------------

local activeAbility = nil
local lastActivate = 0
local activeAbilityCooldown = 1

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		Remotes.PunchAttack:FireServer()
	elseif input.KeyCode == Enum.KeyCode.E then
		if activeAbility then
			Remotes.AbilityActivate:FireServer()
			lastActivate = tick()
		end
	end
end)

-- Cooldown bar tick ----------------------------------------------------------

RunService.Heartbeat:Connect(function()
	if abilityHud.Visible and activeAbility then
		local since = tick() - lastActivate
		local pct = math.clamp(since / activeAbilityCooldown, 0, 1)
		cooldownFill.Size = UDim2.fromScale(pct, 1)
		cooldownFill.BackgroundColor3 = (pct >= 1) and Color3.fromRGB(120, 220, 255) or Color3.fromRGB(255, 200, 100)
	end
end)

-- Match state handler --------------------------------------------------------

local matchEndTime = nil
local selectionEndTime = nil

local function setLobbyVisibility(visible)
	rankPanel.Visible = visible
	statsPanel.Visible = visible
end

Remotes.MatchState.OnClientEvent:Connect(function(payload)
	if payload.phase == "selection" then
		welcome.Visible = false
		setLobbyVisibility(false)
		picker.Visible = true
		pickedName = nil
		pickerSubtitle.Text = "Click an ability — auto-picks if you wait too long"
		pickerTitle.Text = string.format("CHOOSE YOUR POWER  vs  %s  (Elo %d)",
			payload.opponentName or "Opponent", payload.opponentElo or 0)
		selectionEndTime = tick() + (payload.duration or Config.SELECTION_DURATION)
		for name, b in pairs(pickerButtons) do b.BackgroundColor3 = DISPLAY[name].color end
	elseif payload.phase == "intro" then
		picker.Visible = false
		showBanner("ROUND 1", Color3.fromRGB(255, 230, 120), 0.9)
		task.delay(1.0, function()
			showBanner("FIGHT!", Color3.fromRGB(255, 80, 80), 1.0)
		end)
	elseif payload.phase == "fight" then
		picker.Visible = false
		matchEndTime = tick() + (payload.duration or Config.MATCH_DURATION)
		local d = DISPLAY[payload.ability] or { name = payload.ability, color = Color3.new(1,1,1) }
		activeAbility = payload.ability
		activeAbilityCooldown = (DISPLAY[payload.ability] and DISPLAY[payload.ability].cd) or 1
		lastActivate = tick() - activeAbilityCooldown
		abilityNameLbl.Text = d.name
		abilityNameLbl.TextColor3 = d.color
		abilityKeyLbl.Text = "Press E to use"
		abilityHud.Visible = true
		hpFrame.Visible = true
		timerLbl.Visible = true
	elseif payload.phase == "result" then
		matchEndTime = nil
		local color = Color3.fromRGB(220, 220, 220)
		local label = "DRAW"
		if payload.result == "win" then color = Color3.fromRGB(120, 220, 120) label = "VICTORY"
		elseif payload.result == "lose" then color = Color3.fromRGB(220, 120, 120) label = "DEFEAT" end
		local sign = payload.delta and (payload.delta >= 0 and "+" or "") or ""
		local streakTxt = ""
		if payload.streak and payload.streak >= 2 then
			streakTxt = string.format("\n🔥 %d-WIN STREAK", payload.streak)
		end
		showBanner(string.format("%s   %s%d Elo  (now %d)%s",
			label, sign, payload.delta or 0, payload.newElo or 0, streakTxt),
			color, Config.LOBBY_RETURN_DELAY)
	elseif payload.phase == "lobby" then
		abilityHud.Visible = false
		hpFrame.Visible = false
		timerLbl.Visible = false
		picker.Visible = false
		activeAbility = nil
		setLobbyVisibility(true)
	end
end)

Remotes.HpUpdated.OnClientEvent:Connect(function(cur, max)
	hpFill.Size = UDim2.fromScale(math.clamp(cur / max, 0, 1), 1)
	hpLabel.Text = string.format("%d / %d", cur, max)
end)

Remotes.EloUpdated.OnClientEvent:Connect(function(newElo, _delta)
	local tier = Ranks.fromElo(newElo)
	rankBigLbl.Text = tier.name
	rankBigLbl.TextColor3 = tier.accent
	rankEloLbl.Text = "Elo: " .. tostring(newElo)
	progressFill.Size = UDim2.fromScale(Ranks.progress(newElo), 1)
	progressFill.BackgroundColor3 = tier.accent
end)

Remotes.StatsUpdated.OnClientEvent:Connect(function(stats)
	winsLbl.Text = "Wins: " .. tostring(stats.wins)
	lossesLbl.Text = "Losses: " .. tostring(stats.losses)
	local total = stats.wins + stats.losses
	local rate = total > 0 and math.floor(100 * stats.wins / total + 0.5) or 0
	winRateLbl.Text = total > 0 and ("Win rate: " .. rate .. "%") or "Win rate: —"
	streakLbl.Text = "Streak: " .. tostring(stats.streak)
	bestStreakLbl.Text = "Best streak: " .. tostring(stats.bestStreak)
end)

-- Initial pull of own elo + stats so panels populate immediately.
task.spawn(function()
	local ok, elo = pcall(function() return Remotes.GetMyElo:InvokeServer() end)
	if ok and type(elo) == "number" then
		local tier = Ranks.fromElo(elo)
		rankBigLbl.Text = tier.name
		rankBigLbl.TextColor3 = tier.accent
		rankEloLbl.Text = "Elo: " .. tostring(elo)
		progressFill.Size = UDim2.fromScale(Ranks.progress(elo), 1)
		progressFill.BackgroundColor3 = tier.accent
	end
	local ok2, stats = pcall(function() return Remotes.GetMyStats:InvokeServer() end)
	if ok2 and type(stats) == "table" then
		winsLbl.Text = "Wins: " .. tostring(stats.wins or 0)
		lossesLbl.Text = "Losses: " .. tostring(stats.losses or 0)
		local total = (stats.wins or 0) + (stats.losses or 0)
		local rate = total > 0 and math.floor(100 * (stats.wins or 0) / total + 0.5) or 0
		winRateLbl.Text = total > 0 and ("Win rate: " .. rate .. "%") or "Win rate: —"
		streakLbl.Text = "Streak: " .. tostring(stats.streak or 0)
		bestStreakLbl.Text = "Best streak: " .. tostring(stats.bestStreak or 0)
	end
end)

-- Timer update ---------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	if matchEndTime then
		local remain = math.max(0, matchEndTime - tick())
		timerLbl.Text = string.format("%d", math.ceil(remain))
		-- Pulse red on the final 5 seconds.
		if remain <= 5 then
			timerLbl.TextColor3 = Color3.fromRGB(255, 90, 90)
		else
			timerLbl.TextColor3 = Color3.fromRGB(255, 230, 120)
		end
	end
	if selectionEndTime and picker.Visible then
		local remain = math.max(0, selectionEndTime - tick())
		pickerTimer.Text = string.format("Auto-pick in %ds", math.ceil(remain))
	end
end)

print("[SuperpowerShowdown] Client UI ready.")
