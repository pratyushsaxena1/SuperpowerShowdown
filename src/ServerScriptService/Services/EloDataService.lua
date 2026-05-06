local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.SharedModules.GameConfig)
local EloCalc = require(ReplicatedStorage.SharedModules.EloCalc)
local Ranks = require(ReplicatedStorage.SharedModules.Ranks)

-- Bumping the version effectively wipes everyone's stored Elo: the new
-- key namespace has no data so every player starts fresh at GameConfig.DefaultElo
-- (currently 0) on first load.
local EloStore = DataStoreService:GetDataStore("DuelEloV2_Reset")
local EloUpdated = ReplicatedStorage.RemoteEvents.EloUpdated
local GetEloData = ReplicatedStorage.RemoteEvents.GetEloData
local GetTopPlayers = ReplicatedStorage.RemoteEvents:FindFirstChild("GetTopPlayers")

local EloDataService = {}

local sessionData = {}
local saveLocks = {}

local function key(player) return "u_" .. player.UserId end

local function loadPlayer(player)
	local data = { elo = GameConfig.DefaultElo, wins = 0, losses = 0, matches = 0,
		bestStreak = 0, lastDailyClaim = 0 }
	local ok, stored = pcall(function() return EloStore:GetAsync(key(player)) end)
	if ok and typeof(stored) == "table" then
		data.elo = stored.elo or data.elo
		data.wins = stored.wins or 0
		data.losses = stored.losses or 0
		data.matches = stored.matches or 0
		data.bestStreak = stored.bestStreak or 0
		data.lastDailyClaim = stored.lastDailyClaim or 0
	end
	sessionData[player.UserId] = data
	player:SetAttribute("Elo", data.elo)
	player:SetAttribute("Wins", data.wins)
	player:SetAttribute("Losses", data.losses)
	player:SetAttribute("BestStreak", data.bestStreak)
end

local function savePlayer(player)
	local data = sessionData[player.UserId]
	if not data then return end
	if saveLocks[player.UserId] then return end
	saveLocks[player.UserId] = true
	pcall(function() EloStore:SetAsync(key(player), data) end)
	saveLocks[player.UserId] = false
end

local function attachNametag(character, player)
	local head = character:WaitForChild("Head", 5)
	if not head then return end
	local old = head:FindFirstChild("EloTag")
	if old then old:Destroy() end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EloTag"
	-- Bigger billboard now that there are three lines (name, rank, elo).
	billboard.Size = UDim2.new(6.4, 0, 1.9, 0)
	billboard.StudsOffset = Vector3.new(0, 2.7, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.42, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.Text = player.DisplayName
	nameLabel.Parent = billboard

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "RankLabel"
	rankLabel.Position = UDim2.new(0, 0, 0.42, 0)
	rankLabel.Size = UDim2.new(1, 0, 0.32, 0)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Font = Enum.Font.GothamBlack
	rankLabel.TextScaled = true
	rankLabel.TextStrokeTransparency = 0.3
	rankLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	rankLabel.Text = ""
	rankLabel.Parent = billboard

	local eloLabel = Instance.new("TextLabel")
	eloLabel.Name = "EloLabel"
	eloLabel.Position = UDim2.new(0, 0, 0.74, 0)
	eloLabel.Size = UDim2.new(1, 0, 0.26, 0)
	eloLabel.BackgroundTransparency = 1
	eloLabel.Font = Enum.Font.Gotham
	eloLabel.TextScaled = true
	eloLabel.TextColor3 = Color3.fromRGB(220, 220, 240)
	eloLabel.TextStrokeTransparency = 0.4
	eloLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	eloLabel.Text = "Elo " .. (player:GetAttribute("Elo") or GameConfig.DefaultElo)
	eloLabel.Parent = billboard

	-- Initial rank fill.
	local elo = player:GetAttribute("Elo") or GameConfig.DefaultElo
	local tier = Ranks.fromElo(elo)
	rankLabel.Text = string.upper(tier.name)
	rankLabel.TextColor3 = tier.accent

	-- Visibility: shown only in the lobby (no InMatch attribute on the
	-- player) and only when the character isn't invisible. This way two
	-- players fighting don't see each other's name+Elo floating above
	-- their heads — only their HP bars on the HUD.
	local function refreshVisibility()
		local invisible = character:GetAttribute("IsInvisible") == true
		local inMatch = player:GetAttribute("InMatch") == true
		billboard.Enabled = not invisible and not inMatch
	end
	refreshVisibility()
	character:GetAttributeChangedSignal("IsInvisible"):Connect(refreshVisibility)
	player:GetAttributeChangedSignal("InMatch"):Connect(refreshVisibility)
end

local function updateNametag(player)
	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("EloTag")
	if not tag then return end
	local elo = player:GetAttribute("Elo") or GameConfig.DefaultElo
	local tier = Ranks.fromElo(elo)
	local rankLabel = tag:FindFirstChild("RankLabel")
	if rankLabel then
		rankLabel.Text = string.upper(tier.name)
		rankLabel.TextColor3 = tier.accent
	end
	local eloLabel = tag:FindFirstChild("EloLabel")
	if eloLabel then
		eloLabel.Text = "Elo " .. elo
	end
end

function EloDataService.getElo(player)
	local data = sessionData[player.UserId]
	return data and data.elo or GameConfig.DefaultElo
end

-- Bump the persistent best-streak high-water mark. Called by ArenaManager
-- whenever a player's current streak hits a new personal high.
function EloDataService.recordBestStreak(player, n)
	local data = sessionData[player.UserId]
	if not data then return end
	if (data.bestStreak or 0) >= n then return end
	data.bestStreak = n
	player:SetAttribute("BestStreak", n)
	task.spawn(savePlayer, player)
end

function EloDataService.applyResult(playerA, playerB, result)
	local eloA = EloDataService.getElo(playerA)
	local eloB = EloDataService.getElo(playerB)
	local dA, dB
	if result == "draw" then
		dA, dB = 0, 0
	elseif result == "A" then
		dA, dB = EloCalc.compute(eloA, eloB)
	else
		dB, dA = EloCalc.compute(eloB, eloA)
	end

	local minElo = GameConfig.MinElo or 0
	local effectiveDeltas = {}
	for _, pair in ipairs({ { playerA, dA, result == "A", "A" }, { playerB, dB, result == "B", "B" } }) do
		local p, d, won, sideKey = pair[1], pair[2], pair[3], pair[4]
		local data = sessionData[p.UserId]
		if data then
			local before = data.elo
			local after = math.max(minElo, before + d)
			local effD = after - before
			data.elo = after
			data.matches += 1
			if result == "draw" then
				-- nothing
			elseif won then
				data.wins += 1
			else
				data.losses += 1
			end
			p:SetAttribute("Elo", data.elo)
			p:SetAttribute("Wins", data.wins)
			p:SetAttribute("Losses", data.losses)
			updateNametag(p)
			EloUpdated:FireClient(p, { elo = data.elo, delta = effD, result = result })
			task.spawn(savePlayer, p)
			effectiveDeltas[sideKey] = effD
		end
	end
	return effectiveDeltas.A or 0, effectiveDeltas.B or 0
end

function EloDataService.init()
	Players.PlayerAdded:Connect(function(player)
		loadPlayer(player)
		player.CharacterAdded:Connect(function(char)
			task.wait(0.25)
			attachNametag(char, player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
		sessionData[player.UserId] = nil
	end)
	if GetTopPlayers then
		GetTopPlayers.OnServerInvoke = function(_invoker)
			-- Top 10 by current-session Elo. Cheap O(N log N) scan over
			-- live players; the tab panel is only opened on demand so it
			-- doesn't poll on a timer.
			local list = {}
			for _, p in ipairs(Players:GetPlayers()) do
				local d = sessionData[p.UserId]
				if d then
					table.insert(list, {
						name = p.DisplayName or p.Name,
						userId = p.UserId,
						elo = d.elo,
						wins = d.wins,
						losses = d.losses,
					})
				end
			end
			table.sort(list, function(a, b) return a.elo > b.elo end)
			while #list > 10 do table.remove(list) end
			return list
		end
	end

	GetEloData.OnServerInvoke = function(player)
		local d = sessionData[player.UserId]
		if not d then return { elo = GameConfig.DefaultElo, wins = 0, losses = 0, bestStreak = 0 } end
		return {
			elo = d.elo,
			wins = d.wins,
			losses = d.losses,
			bestStreak = d.bestStreak or 0,
		}
	end
	task.spawn(function()
		while true do
			task.wait(120)
			for _, p in ipairs(Players:GetPlayers()) do
				savePlayer(p)
			end
		end
	end)

	-- Flush every in-session player's Elo / W-L record before the server
	-- actually shuts down. PlayerRemoving races the shutdown otherwise, so
	-- the final match of the session could be lost on a crash / BindToClose.
	game:BindToClose(function()
		local plist = Players:GetPlayers()
		if #plist == 0 then return end
		local done = 0
		for _, p in ipairs(plist) do
			-- Bypass the per-player save lock so the shutdown-time write
			-- always goes through even if a save was mid-flight.
			saveLocks[p.UserId] = false
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

return EloDataService
