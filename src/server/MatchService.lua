local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Abilities = require(Shared:WaitForChild("Abilities"))

local MatchService = {}
MatchService.__index = MatchService

function MatchService.new(deps)
	local self = setmetatable({}, MatchService)
	self._elo = deps.elo
	self._combat = deps.combat
	self._pad = deps.pad
	self._matches = {}                  -- [matchId] = match table
	self._playerMatch = {}              -- [player] = matchId
	self._abilityChoice = {}            -- [player] = ability name
	self._abilityState = {}             -- [player] = state table
	self._lastActivate = {}             -- [player] = tick()
	self._matchCounter = 0

	self._combat:SetOnDeath(function(loser, winner) self:_onDeath(loser, winner) end)

	Remotes.AbilityChosen.OnServerEvent:Connect(function(plr, name) self:_onAbilityChosen(plr, name) end)
	Remotes.AbilityActivate.OnServerEvent:Connect(function(plr) self:_onActivate(plr) end)
	Remotes.PunchAttack.OnServerEvent:Connect(function(plr) self._combat:HandlePunch(plr) end)

	return self
end

function MatchService:_clientStateUpdate(match, payload)
	for _, p in ipairs({ match.a, match.b }) do
		Remotes.MatchState:FireClient(p, payload)
	end
end

local function teleportTo(player, position)
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	root.CFrame = CFrame.new(position)
end

function MatchService:Start(a, b)
	self._matchCounter += 1
	local id = self._matchCounter
	local match = {
		id = id,
		a = a, b = b,
		startTime = nil,
		ended = false,
	}
	self._matches[id] = match
	self._playerMatch[a] = id
	self._playerMatch[b] = id

	teleportTo(a, Config.ARENA_A_POS)
	teleportTo(b, Config.ARENA_B_POS)

	self._abilityChoice[a] = nil
	self._abilityChoice[b] = nil

	-- Freeze players until selection done
	self:_freeze(a, true)
	self:_freeze(b, true)

	self:_clientStateUpdate(match, {
		phase = "selection",
		opponentName = b.Name, -- overwritten per-player below
		duration = Config.SELECTION_DURATION,
	})
	Remotes.MatchState:FireClient(a, { phase = "selection", opponentName = b.Name, duration = Config.SELECTION_DURATION })
	Remotes.MatchState:FireClient(b, { phase = "selection", opponentName = a.Name, duration = Config.SELECTION_DURATION })

	task.delay(Config.SELECTION_DURATION, function()
		if match.ended then return end
		if not self._abilityChoice[a] then self._abilityChoice[a] = Config.ABILITIES[math.random(1, #Config.ABILITIES)] end
		if not self._abilityChoice[b] then self._abilityChoice[b] = Config.ABILITIES[math.random(1, #Config.ABILITIES)] end
		self:_beginFight(match)
	end)
end

function MatchService:_freeze(player, frozen)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = frozen and 0 or 16
		hum.JumpHeight = frozen and 0 or 7.2
	end
end

function MatchService:_buildAbilityState(player, abilityName)
	local ability = Abilities.get(abilityName)
	local state = {
		player = player,
		character = player.Character,
		abilityName = abilityName,
		requestSlam = function(p, origin, radius, dmg) self._combat:HandleSlam(p, origin, radius, dmg) end,
	}
	self._abilityState[player] = state
	if ability and ability.onMatchStart then ability.onMatchStart(state) end
end

function MatchService:_onAbilityChosen(player, name)
	local matchId = self._playerMatch[player]
	if not matchId then return end
	local match = self._matches[matchId]
	if not match or match.ended then return end
	if not table.find(Config.ABILITIES, name) then return end
	if match.startTime then return end -- already past selection
	self._abilityChoice[player] = name
end

function MatchService:_beginFight(match)
	match.startTime = tick()
	for _, p in ipairs({ match.a, match.b }) do
		local choice = self._abilityChoice[p]
		self:_buildAbilityState(p, choice)
		self._combat:RegisterMatchPlayer(p, Abilities.get(choice))
		self:_freeze(p, false)
		Remotes.MatchState:FireClient(p, {
			phase = "fight",
			ability = choice,
			opponentAbility = self._abilityChoice[(p == match.a) and match.b or match.a],
			duration = Config.MATCH_DURATION,
		})
	end
	-- Timer
	task.delay(Config.MATCH_DURATION, function()
		if match.ended then return end
		self:_endByTimer(match)
	end)
end

function MatchService:_onActivate(player)
	local matchId = self._playerMatch[player]
	if not matchId then return end
	local match = self._matches[matchId]
	if not match or match.ended or not match.startTime then return end

	local state = self._abilityState[player]
	if not state then return end
	local ability = Abilities.get(state.abilityName)
	if not ability then return end

	local now = tick()
	local last = self._lastActivate[player] or 0
	if now - last < (ability.Cooldown or 1) then return end
	self._lastActivate[player] = now

	state.character = player.Character
	if ability.activate then ability.activate(state) end
end

function MatchService:_onDeath(loser, winner)
	local matchId = self._playerMatch[loser]
	if not matchId then return end
	local match = self._matches[matchId]
	if not match or match.ended then return end
	if winner == nil or winner == loser then
		-- treat as draw safety
		self:_finish(match, nil)
	else
		self:_finish(match, winner)
	end
end

function MatchService:_endByTimer(match)
	local hpA = self._combat:GetHP(match.a) or 0
	local hpB = self._combat:GetHP(match.b) or 0
	local winner
	if hpA > hpB then winner = match.a
	elseif hpB > hpA then winner = match.b
	else winner = nil end
	self:_finish(match, winner)
end

function MatchService:_finish(match, winner)
	if match.ended then return end
	match.ended = true

	-- ability cleanup
	for _, p in ipairs({ match.a, match.b }) do
		local s = self._abilityState[p]
		if s then
			local ab = Abilities.get(s.abilityName)
			if ab and ab.cleanup then pcall(ab.cleanup, s) end
		end
		self._abilityState[p] = nil
		self._abilityChoice[p] = nil
		self._lastActivate[p] = nil
		self._combat:UnregisterMatchPlayer(p)
	end

	local newA, newB, dA, dB = self._elo:ApplyMatch(match.a, match.b, winner)

	for _, p in ipairs({ match.a, match.b }) do
		local newElo = (p == match.a) and newA or newB
		local delta  = (p == match.a) and dA or dB
		Remotes.EloUpdated:FireClient(p, newElo, delta)
		local result
		if winner == nil then result = "draw"
		elseif winner == p then result = "win"
		else result = "lose" end
		Remotes.MatchState:FireClient(p, {
			phase = "result",
			result = result,
			newElo = newElo,
			delta = delta,
			duration = Config.LOBBY_RETURN_DELAY,
		})
	end

	task.delay(Config.LOBBY_RETURN_DELAY, function()
		for _, p in ipairs({ match.a, match.b }) do
			self._playerMatch[p] = nil
			self._pad:SetBusy(p, false)
			if p.Parent then
				local char = p.Character
				if char then
					local hum = char:FindFirstChildOfClass("Humanoid")
					if hum then hum.Health = hum.MaxHealth end
				end
				teleportTo(p, Config.LOBBY_SPAWN)
				Remotes.MatchState:FireClient(p, { phase = "lobby" })
			end
		end
		self._matches[match.id] = nil
	end)
end

function MatchService:HandlePlayerLeaving(player)
	local matchId = self._playerMatch[player]
	if not matchId then return end
	local match = self._matches[matchId]
	if not match or match.ended then return end
	local other = (player == match.a) and match.b or match.a
	self:_finish(match, other)
end

return MatchService
