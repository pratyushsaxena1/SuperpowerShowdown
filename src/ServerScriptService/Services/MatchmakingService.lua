local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage.RemoteEvents

local MatchmakingService = {}

local DEFAULT_IDLE_COLOR = Color3.fromRGB(100, 180, 255)
-- Searching/Teleporting colors are intentionally distinct from any pad's
-- BaseColor so the state change is unmistakable.
local SEARCHING_COLOR = Color3.fromRGB(255, 255, 255)
local TELEPORTING_COLOR = Color3.fromRGB(255, 230, 90)
-- Time after TouchEnded before we accept that the player has actually left.
-- Roblox fires Touched/TouchEnded repeatedly while a character idles on a
-- part, so without this the player flicks out of the queue and back in.
local LEAVE_DEBOUNCE = 0.35

local queue = {}
local playerOnPad = {}
local padPlayers = {}
local pendingLeave = {} -- [userId] = job id, used to cancel a stale leave
local ArenaManager
local AIMatchCoordinator
local EloDataService
local lobbyReturnCFrame

local function padIdleColor(pad)
	local c = pad:GetAttribute("BaseColor")
	if typeof(c) == "Color3" then return c end
	return DEFAULT_IDLE_COLOR
end

local function updatePadVisual(pad, text, color)
	local billboard = pad:FindFirstChild("PadStatus")
	if billboard then
		local label = billboard:FindFirstChildWhichIsA("TextLabel")
		if label then label.Text = text end
	end
	if color and pad:IsA("BasePart") then
		pad.Color = color
	end
	local light = pad:FindFirstChildWhichIsA("PointLight")
	if light and color then light.Color = color end
end

local function resetPadIdle(pad)
	updatePadVisual(pad, "Step on to duel", padIdleColor(pad))
end

local function removeFromQueue(userId)
	for i, q in ipairs(queue) do
		if q.userId == userId then
			table.remove(queue, i)
			return
		end
	end
end

local function playerLeavePad(player)
	local pad = playerOnPad[player.UserId]
	if not pad then return end
	padPlayers[pad] = nil
	playerOnPad[player.UserId] = nil
	removeFromQueue(player.UserId)
	resetPadIdle(pad)
end

-- True if the player's HRP is positioned over the pad's footprint. Used to
-- confirm a TouchEnded actually corresponds to walking off vs idle wobble.
local function isPlayerStandingOnPad(player, pad)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local rel = pad.CFrame:PointToObjectSpace(hrp.Position)
	local half = pad.Size * 0.5
	return math.abs(rel.X) <= half.X + 1.5
		and math.abs(rel.Z) <= half.Z + 1.5
		and rel.Y > -1 and rel.Y < 8
end

-- Players on cross-pad (different PadPair) won't be matched until at least
-- one of them has been waiting this long. Gives friends a chance to step
-- on matching pads and play each other directly before the queue starts
-- pairing strangers across pads.
local CROSS_PAD_WAIT = 8

local function popQueueIndices(i, j)
	local later = math.max(i, j)
	local earlier = math.min(i, j)
	local b = queue[later]
	local a = queue[earlier]
	table.remove(queue, later)
	table.remove(queue, earlier)
	return a, b
end

local function startMatchPair(a, b)
	local pA = Players:GetPlayerByUserId(a.userId)
	local pB = Players:GetPlayerByUserId(b.userId)
	if not (pA and pB) then return end

	local padA = playerOnPad[pA.UserId]
	local padB = playerOnPad[pB.UserId]
	if padA then updatePadVisual(padA, "Match found!", TELEPORTING_COLOR) end
	if padB then updatePadVisual(padB, "Match found!", TELEPORTING_COLOR) end

	task.spawn(function()
		task.wait(1)
		if padA then
			padPlayers[padA] = nil
			resetPadIdle(padA)
		end
		if padB then
			padPlayers[padB] = nil
			resetPadIdle(padB)
		end
		playerOnPad[pA.UserId] = nil
		playerOnPad[pB.UserId] = nil

		ArenaManager.startMatch(pA, pB, EloDataService, lobbyReturnCFrame)
	end)
end

local function tryMatch()
	if #queue < 2 then return end

	-- 1. Direct pair match: two players on pads that share a PadPair attribute
	--    play each other, regardless of Elo. This is the "friends queueing
	--    together" case — matching colors should always pair.
	for i = 1, #queue - 1 do
		local padI = playerOnPad[queue[i].userId]
		local pairI = padI and padI:GetAttribute("PadPair")
		if pairI then
			for j = i + 1, #queue do
				local padJ = playerOnPad[queue[j].userId]
				local pairJ = padJ and padJ:GetAttribute("PadPair")
				if pairJ == pairI and padJ ~= padI then
					local a, b = popQueueIndices(i, j)
					startMatchPair(a, b)
					return
				end
			end
		end
	end

	-- 2. Cross-pad fallback by Elo, but only if someone has been waiting
	--    long enough that we shouldn't keep them stuck just because their
	--    pair pad is empty.
	local now = os.clock()
	local oldest = 0
	for _, q in ipairs(queue) do
		oldest = math.max(oldest, now - q.enterTime)
	end
	if oldest < CROSS_PAD_WAIT then return end

	table.sort(queue, function(x, y) return x.elo < y.elo end)
	local bestI, bestJ, bestDiff = 1, 2, math.huge
	for i = 1, #queue - 1 do
		local diff = math.abs(queue[i].elo - queue[i + 1].elo)
		if diff < bestDiff then
			bestDiff = diff
			bestI, bestJ = i, i + 1
		end
	end
	local a, b = popQueueIndices(bestI, bestJ)
	startMatchPair(a, b)
end

local function playerEnterPad(pad, player)
	-- Cancel any pending "leave" for this player; they're back on a pad.
	pendingLeave[player.UserId] = nil
	if playerOnPad[player.UserId] then return end
	if padPlayers[pad] then return end
	if player:GetAttribute("InMatch") then return end
	padPlayers[pad] = player
	playerOnPad[player.UserId] = pad
	local elo = EloDataService.getElo(player)
	table.insert(queue, { userId = player.UserId, elo = elo, enterTime = os.clock() })
	updatePadVisual(pad, "Searching...", SEARCHING_COLOR)
	tryMatch()
	-- Re-evaluate after the cross-pad wait so solos on different pads
	-- still get matched even if no other player joins/leaves the queue.
	task.delay(CROSS_PAD_WAIT + 0.2, tryMatch)
end

local function hookPad(pad)
	if not pad:IsA("BasePart") then return end
	pad.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		if not char then return end
		local player = Players:GetPlayerFromCharacter(char)
		if player then playerEnterPad(pad, player) end
	end)
	pad.TouchEnded:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		if not char then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player or playerOnPad[player.UserId] ~= pad then return end
		local token = {}
		pendingLeave[player.UserId] = token
		task.delay(LEAVE_DEBOUNCE, function()
			-- Only actually leave if the debounce token wasn't replaced
			-- (a re-Touched would clear it) and the player really walked off.
			if pendingLeave[player.UserId] ~= token then return end
			pendingLeave[player.UserId] = nil
			if playerOnPad[player.UserId] ~= pad then return end
			if isPlayerStandingOnPad(player, pad) then return end
			playerLeavePad(player)
		end)
	end)
	resetPadIdle(pad)
end

local function hookAIPad(pad)
	if not pad:IsA("BasePart") then return end
	local busy = {}
	pad.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		if not char then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end
		if player:GetAttribute("InMatch") then return end
		if busy[player.UserId] then return end
		busy[player.UserId] = true
		task.spawn(function()
			if AIMatchCoordinator then
				AIMatchCoordinator.startMatch(player, EloDataService, lobbyReturnCFrame)
			end
			busy[player.UserId] = nil
		end)
	end)
	local billboard = pad:FindFirstChild("PadStatus")
	if billboard then
		local label = billboard:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text = "Train vs AI"
			label.TextColor3 = Color3.fromRGB(170, 245, 180)
		end
	end
end

function MatchmakingService.registerLobby(lobbyModel, returnCFrame)
	lobbyReturnCFrame = returnCFrame
	for _, desc in ipairs(lobbyModel:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name:sub(1, 5) == "AIPad" then
			hookAIPad(desc)
		elseif desc:IsA("BasePart") and desc.Name:sub(1, 7) == "DuelPad" then
			hookPad(desc)
		end
	end
end

function MatchmakingService.init(arenaManager, eloService, aiMatchCoordinator)
	ArenaManager = arenaManager
	EloDataService = eloService
	AIMatchCoordinator = aiMatchCoordinator
	Players.PlayerRemoving:Connect(function(player)
		pendingLeave[player.UserId] = nil
		playerLeavePad(player)
	end)
end

return MatchmakingService
