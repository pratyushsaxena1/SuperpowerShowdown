local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- Display labels for ability internal names
local DISPLAY = {
	Flying = { name = "Flying",        color = Color3.fromRGB(120, 200, 255), desc = "Press E to fly upward" },
	Teleportation = { name = "Teleport",      color = Color3.fromRGB(200, 120, 255), desc = "Press E to blink 30 studs forward" },
	SuperStrength = { name = "Super Strength",color = Color3.fromRGB(255, 120, 80),  desc = "Press E for ground slam (3x punch dmg)" },
	SuperSpeed    = { name = "Super Speed",   color = Color3.fromRGB(255, 230, 100), desc = "Press E for sprint burst (always 2x speed)" },
	Invisibility  = { name = "Invisibility",  color = Color3.fromRGB(180, 180, 200), desc = "Press E to vanish for 4s (1.5x punch dmg)" },
}

-- Single ScreenGui hosts everything
local gui = Instance.new("ScreenGui")
gui.Name = "SuperpowerShowdownUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = pg

local function makeFrame(parent, props)
	local f = Instance.new("Frame")
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
	for k, v in pairs(props or {}) do b[k] = v end
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = b
	return b
end

-- LOBBY WELCOME OVERLAY -------------------------------------------------------

local welcome = makeFrame(gui, {
	Name = "Welcome",
	Size = UDim2.fromScale(0.5, 0.45),
	Position = UDim2.fromScale(0.25, 0.27),
	BackgroundColor3 = Color3.fromRGB(20, 24, 40),
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
})
local wcorner = Instance.new("UICorner") wcorner.CornerRadius = UDim.new(0, 18) wcorner.Parent = welcome
makeLabel(welcome, {
	Size = UDim2.new(1, -20, 0, 60),
	Position = UDim2.fromOffset(10, 10),
	Text = "SUPERPOWER SHOWDOWN",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 230, 120),
})
makeLabel(welcome, {
	Size = UDim2.new(1, -40, 0, 40),
	Position = UDim2.fromOffset(20, 75),
	Text = "1v1 ranked duels — first to 0 HP loses, 60s timer",
	TextScaled = true,
})
makeLabel(welcome, {
	Size = UDim2.new(1, -40, 0, 80),
	Position = UDim2.fromOffset(20, 125),
	Text = "Stand on a glowing pad (blue or red) for 3 seconds to queue.\nIf both pads have one player, you'll be paired across pads.\nOtherwise the closest-Elo pair on a single pad is matched.",
	TextWrapped = true,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(220, 220, 230),
})
makeLabel(welcome, {
	Size = UDim2.new(1, -40, 0, 60),
	Position = UDim2.new(0, 20, 1, -90),
	Text = "Controls:  LEFT-CLICK = Attack    •    E = Ability",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(120, 220, 255),
})
local closeBtn = makeButton(welcome, {
	Size = UDim2.fromOffset(140, 40),
	Position = UDim2.new(0.5, -70, 1, -50),
	Text = "Got it",
	BackgroundColor3 = Color3.fromRGB(60, 200, 120),
})
closeBtn.MouseButton1Click:Connect(function() welcome.Visible = false end)

-- CONTROLS STRIP (always visible during gameplay) -----------------------------

local controlsStrip = makeFrame(gui, {
	Name = "Controls",
	Size = UDim2.new(0, 360, 0, 36),
	Position = UDim2.new(0.5, -180, 1, -50),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.4,
	BorderSizePixel = 0,
})
local cscorner = Instance.new("UICorner") cscorner.CornerRadius = UDim.new(0, 10) cscorner.Parent = controlsStrip
makeLabel(controlsStrip, {
	Size = UDim2.fromScale(1, 1),
	Text = "LEFT-CLICK = Attack    •    E = Ability",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(220, 220, 240),
})

-- ABILITY HUD (current power + key) -------------------------------------------

local abilityHud = makeFrame(gui, {
	Name = "AbilityHUD",
	Size = UDim2.new(0, 260, 0, 90),
	Position = UDim2.new(1, -280, 1, -150),
	BackgroundColor3 = Color3.fromRGB(20, 24, 40),
	BackgroundTransparency = 0.15,
	Visible = false,
	BorderSizePixel = 0,
})
local ahcorner = Instance.new("UICorner") ahcorner.CornerRadius = UDim.new(0, 10) ahcorner.Parent = abilityHud
local abilityNameLbl = makeLabel(abilityHud, {
	Size = UDim2.new(1, -20, 0, 32),
	Position = UDim2.fromOffset(10, 5),
	Text = "Power",
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
})
local abilityKeyLbl = makeLabel(abilityHud, {
	Size = UDim2.new(1, -20, 0, 26),
	Position = UDim2.fromOffset(10, 38),
	Text = "Press E to use",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 230, 120),
	TextXAlignment = Enum.TextXAlignment.Left,
})
local cooldownBar = makeFrame(abilityHud, {
	Size = UDim2.new(1, -20, 0, 8),
	Position = UDim2.new(0, 10, 1, -16),
	BackgroundColor3 = Color3.fromRGB(60, 60, 80),
	BorderSizePixel = 0,
})
local cooldownFill = makeFrame(cooldownBar, {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(120, 220, 255),
	BorderSizePixel = 0,
})

-- HP BAR ----------------------------------------------------------------------

local hpFrame = makeFrame(gui, {
	Name = "HP",
	Size = UDim2.new(0, 360, 0, 30),
	Position = UDim2.new(0.5, -180, 0, 18),
	BackgroundColor3 = Color3.fromRGB(40, 40, 40),
	Visible = false,
	BorderSizePixel = 0,
})
local hpcorner = Instance.new("UICorner") hpcorner.CornerRadius = UDim.new(0, 8) hpcorner.Parent = hpFrame
local hpFill = makeFrame(hpFrame, {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(220, 80, 80),
	BorderSizePixel = 0,
})
local hpfcorner = Instance.new("UICorner") hpfcorner.CornerRadius = UDim.new(0, 8) hpfcorner.Parent = hpFill
local hpLabel = makeLabel(hpFrame, {
	Size = UDim2.fromScale(1, 1),
	Text = "100 / 100",
	TextScaled = true,
})

-- TIMER -----------------------------------------------------------------------

local timerLbl = makeLabel(gui, {
	Name = "Timer",
	Size = UDim2.new(0, 200, 0, 50),
	Position = UDim2.new(0.5, -100, 0, 56),
	Text = "",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 230, 120),
	Visible = false,
})

-- BANNER (fades in/out) -------------------------------------------------------

local banner = makeLabel(gui, {
	Name = "Banner",
	Size = UDim2.new(1, 0, 0, 90),
	Position = UDim2.fromScale(0, 0.32),
	Text = "",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 230, 120),
	Visible = false,
})

local function showBanner(text, color, seconds)
	banner.Text = text
	banner.TextColor3 = color or Color3.fromRGB(255, 230, 120)
	banner.Visible = true
	task.delay(seconds or 2.5, function() banner.Visible = false end)
end

-- ABILITY PICKER --------------------------------------------------------------

local picker = makeFrame(gui, {
	Name = "Picker",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.35,
	Visible = false,
	BorderSizePixel = 0,
})
local pickerTitle = makeLabel(picker, {
	Size = UDim2.new(1, 0, 0, 80),
	Position = UDim2.fromOffset(0, 40),
	Text = "CHOOSE YOUR POWER",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 230, 120),
})
local pickerSubtitle = makeLabel(picker, {
	Size = UDim2.new(1, 0, 0, 36),
	Position = UDim2.fromOffset(0, 120),
	Text = "Click an ability — auto-picks if you wait too long",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(220, 220, 240),
})
local pickerTimer = makeLabel(picker, {
	Size = UDim2.new(1, 0, 0, 36),
	Position = UDim2.fromOffset(0, 158),
	Text = "",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 200, 200),
})
local pickerRow = makeFrame(picker, {
	Name = "Row",
	Size = UDim2.new(1, -80, 0, 220),
	Position = UDim2.new(0, 40, 0.5, -60),
	BackgroundTransparency = 1,
})
local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.Padding = UDim.new(0, 14)
listLayout.Parent = pickerRow

local pickerButtons = {}
local pickedName = nil

for _, abilityName in ipairs(Config.ABILITIES) do
	local d = DISPLAY[abilityName]
	local btn = makeButton(pickerRow, {
		Size = UDim2.new(0, 200, 1, 0),
		BackgroundColor3 = d.color,
		Text = "",
	})
	makeLabel(btn, {
		Size = UDim2.new(1, -10, 0, 50),
		Position = UDim2.fromOffset(5, 8),
		Text = d.name,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(20, 20, 30),
	})
	makeLabel(btn, {
		Size = UDim2.new(1, -16, 1, -64),
		Position = UDim2.fromOffset(8, 60),
		Text = d.desc,
		TextScaled = true,
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(20, 20, 30),
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

-- INPUT -----------------------------------------------------------------------

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

-- Cooldown bar tick
RunService.Heartbeat:Connect(function()
	if abilityHud.Visible and activeAbility then
		local since = tick() - lastActivate
		local pct = math.clamp(since / activeAbilityCooldown, 0, 1)
		cooldownFill.Size = UDim2.fromScale(pct, 1)
		cooldownFill.BackgroundColor3 = (pct >= 1) and Color3.fromRGB(120, 220, 255) or Color3.fromRGB(255, 200, 100)
	end
end)

-- MATCH STATE HANDLER ---------------------------------------------------------

local matchEndTime = nil
local selectionEndTime = nil

Remotes.MatchState.OnClientEvent:Connect(function(payload)
	if payload.phase == "selection" then
		welcome.Visible = false
		picker.Visible = true
		pickedName = nil
		pickerSubtitle.Text = "Click an ability — auto-picks if you wait too long"
		pickerTitle.Text = "CHOOSE YOUR POWER vs " .. (payload.opponentName or "Opponent")
		selectionEndTime = tick() + (payload.duration or Config.SELECTION_DURATION)
		for name, b in pairs(pickerButtons) do b.BackgroundColor3 = DISPLAY[name].color end
	elseif payload.phase == "fight" then
		picker.Visible = false
		matchEndTime = tick() + (payload.duration or Config.MATCH_DURATION)
		local d = DISPLAY[payload.ability] or { name = payload.ability, color = Color3.new(1,1,1) }
		activeAbility = payload.ability
		activeAbilityCooldown = 1
		-- Cooldowns from per-ability tables (mirror server values)
		local CD = { Flying = 0.1, Teleportation = 4, SuperStrength = 6, SuperSpeed = 6, Invisibility = 10 }
		activeAbilityCooldown = CD[payload.ability] or 1
		lastActivate = tick() - activeAbilityCooldown
		abilityNameLbl.Text = d.name
		abilityNameLbl.TextColor3 = d.color
		abilityKeyLbl.Text = "Press E to use"
		abilityHud.Visible = true
		hpFrame.Visible = true
		timerLbl.Visible = true
		showBanner("YOUR POWER: " .. string.upper(d.name), d.color, 2.2)
	elseif payload.phase == "result" then
		matchEndTime = nil
		local color = Color3.fromRGB(220, 220, 220)
		local label = "DRAW"
		if payload.result == "win" then color = Color3.fromRGB(120, 220, 120) label = "VICTORY"
		elseif payload.result == "lose" then color = Color3.fromRGB(220, 120, 120) label = "DEFEAT" end
		local sign = payload.delta and (payload.delta >= 0 and "+" or "") or ""
		showBanner(string.format("%s   %s%d Elo  (now %d)", label, sign, payload.delta or 0, payload.newElo or 0),
			color, Config.LOBBY_RETURN_DELAY)
	elseif payload.phase == "lobby" then
		abilityHud.Visible = false
		hpFrame.Visible = false
		timerLbl.Visible = false
		picker.Visible = false
		activeAbility = nil
	end
end)

Remotes.HpUpdated.OnClientEvent:Connect(function(cur, max)
	hpFill.Size = UDim2.fromScale(math.clamp(cur / max, 0, 1), 1)
	hpLabel.Text = string.format("%d / %d", cur, max)
end)

-- TIMER UPDATE ----------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	if matchEndTime then
		local remain = math.max(0, matchEndTime - tick())
		timerLbl.Text = string.format("%d", math.ceil(remain))
	end
	if selectionEndTime and picker.Visible then
		local remain = math.max(0, selectionEndTime - tick())
		pickerTimer.Text = string.format("Auto-pick in %ds", math.ceil(remain))
	end
end)

print("[SuperpowerShowdown] Client UI ready.")
