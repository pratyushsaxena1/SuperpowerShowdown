local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PadService = {}
PadService.__index = PadService

function PadService.new(eloService, onMatchReady)
	local self = setmetatable({}, PadService)
	self._elo = eloService
	self._onMatchReady = onMatchReady
	self._padA = nil
	self._padB = nil
	self._holdersA = {}  -- [player] = enterTime
	self._holdersB = {}  -- [player] = enterTime
	self._busy = {}      -- [player] = true while in a match
	return self
end

function PadService:_makePad(name, position, color)
	local pad = Instance.new("Part")
	pad.Name = name
	pad.Anchored = true
	pad.Size = Vector3.new(8, 1, 8)
	pad.Position = position
	pad.Color = color
	pad.Material = Enum.Material.Neon
	pad.Parent = workspace

	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(180, 50)
	label.StudsOffset = Vector3.new(0, 4, 0)
	label.AlwaysOnTop = true
	label.Parent = pad
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	txt.Text = "Stand here\nto duel"
	txt.TextColor3 = Color3.new(1, 1, 1)
	txt.TextStrokeTransparency = 0
	txt.Font = Enum.Font.GothamBold
	txt.TextScaled = true
	txt.Parent = label

	return pad
end

function PadService:Build()
	self._padA = self:_makePad("PadA", Config.PAD_A_POS, Color3.fromRGB(120, 200, 255))
	self._padB = self:_makePad("PadB", Config.PAD_B_POS, Color3.fromRGB(255, 140, 140))
end

function PadService:SetBusy(player, busy)
	if busy then
		self._busy[player] = true
		self._holdersA[player] = nil
		self._holdersB[player] = nil
	else
		self._busy[player] = nil
	end
end

local function isOnPad(char, pad)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local d = root.Position - pad.Position
	return math.abs(d.X) <= pad.Size.X / 2 + 1
		and math.abs(d.Z) <= pad.Size.Z / 2 + 1
		and d.Y >= 0 and d.Y <= 6
end

local function pickClosestElo(holders, eloService)
	local list = {}
	for plr, _ in pairs(holders) do
		table.insert(list, { player = plr, elo = eloService:Get(plr) })
	end
	if #list < 2 then return nil end
	table.sort(list, function(a, b) return a.elo < b.elo end)
	-- pick the pair with the smallest gap
	local bestI, bestGap = 1, math.huge
	for i = 1, #list - 1 do
		local gap = list[i + 1].elo - list[i].elo
		if gap < bestGap then bestGap, bestI = gap, i end
	end
	return list[bestI].player, list[bestI + 1].player
end

function PadService:Start()
	RunService.Heartbeat:Connect(function()
		if not self._padA or not self._padB then return end
		for _, plr in ipairs(Players:GetPlayers()) do
			if not self._busy[plr] then
				local char = plr.Character
				if char then
					if isOnPad(char, self._padA) then
						self._holdersA[plr] = self._holdersA[plr] or tick()
					else
						self._holdersA[plr] = nil
					end
					if isOnPad(char, self._padB) then
						self._holdersB[plr] = self._holdersB[plr] or tick()
					else
						self._holdersB[plr] = nil
					end
				end
			end
		end

		-- Build candidate pools (held >= PAD_HOLD_TIME)
		local now = tick()
		local readyA, readyB = {}, {}
		for plr, t in pairs(self._holdersA) do
			if now - t >= Config.PAD_HOLD_TIME then readyA[plr] = true end
		end
		for plr, t in pairs(self._holdersB) do
			if now - t >= Config.PAD_HOLD_TIME then readyB[plr] = true end
		end

		-- Cross-pad pairing first (one A holder + one B holder)
		local hasA, hasB = next(readyA), next(readyB)
		if hasA and hasB then
			local a, b = nil, nil
			for plr, _ in pairs(readyA) do a = plr break end
			for plr, _ in pairs(readyB) do b = plr break end
			if a and b and a ~= b then
				self:SetBusy(a, true) self:SetBusy(b, true)
				self._onMatchReady(a, b)
				return
			end
		end
		-- Same-pad fallback: closest-Elo pair on either pad
		local a, b = pickClosestElo(readyA, self._elo)
		if not a then a, b = pickClosestElo(readyB, self._elo) end
		if a and b then
			self:SetBusy(a, true) self:SetBusy(b, true)
			self._onMatchReady(a, b)
		end
	end)
end

return PadService
