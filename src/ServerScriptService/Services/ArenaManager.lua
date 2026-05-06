local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.SharedModules.GameConfig)
local AbilityDefs = require(ReplicatedStorage.SharedModules.AbilityDefs)

local Remotes = ReplicatedStorage.RemoteEvents

local ArenaManager = {}

local CurrencyService = require(script.Parent.CurrencyService)
local EloDataService = require(script.Parent.EloDataService)

local activeMatches = {}
local nextArenaIndex = 0
local CombatService

-- Win rewards (in Coins). Tuned with the Coin store prices in mind: a
-- skin costs 5,000 coins, so ~100 PvP wins to grind one. Direct Robux
-- purchase stays the better deal — coins are the slow free path.
local COINS_WIN = 50
local COINS_DRAW = 20
local COINS_LOSS = 10

-- Per-user PvP win streak (resets on loss/draw, ephemeral per server
-- session). Streak milestones award a flat bonus + a banner title that
-- ships with the MatchEnded payload so the client can celebrate it. AI
-- matches deliberately don't count — streaks are PvP-only so they feel
-- prestigious instead of farmable.
local streaks = {}
local STREAK_TITLES = {
	[3]  = "Hot streak!",
	[5]  = "On fire!",
	[10] = "Unstoppable!",
	[15] = "Legendary!",
	[25] = "Champion!",
}
local STREAK_BONUS_COINS = 25

local function applyStreak(player, won)
	if not player.Parent then return nil, 0, 0 end
	local uid = player.UserId
	if not won then
		streaks[uid] = 0
		player:SetAttribute("Streak", 0)
		return nil, 0, 0
	end
	local n = (streaks[uid] or 0) + 1
	streaks[uid] = n
	player:SetAttribute("Streak", n)
	-- Bump persistent best streak via EloDataService (for the lobby HUD's
	-- "Best streak" line). The setter is no-op if EloDataService doesn't
	-- expose it (older revisions of the module).
	if EloDataService and EloDataService.recordBestStreak then
		EloDataService.recordBestStreak(player, n)
	end
	local title = STREAK_TITLES[n]
	local bonus = 0
	if title then
		bonus = STREAK_BONUS_COINS
		CurrencyService.add(player, bonus)
		-- Broadcast to everyone in the server. The whole point of streaks
		-- is social pressure: hyping the streaker on chat-style banners
		-- gets the lobby trying to dethrone them, which drives matches.
		local Broadcast = ReplicatedStorage.RemoteEvents:FindFirstChild("BroadcastNotification")
		if Broadcast then
			Broadcast:FireAllClients({
				kind = "streak",
				playerName = player.DisplayName or player.Name,
				count = n,
				title = title,
			})
		end
	end
	return title, bonus, n
end

-- Arena placement grid: all arenas live at Y = 5000 to avoid float precision
-- drift at very high Y, and are laid out along X in a row 2000 studs apart so
-- they never overlap no matter how many concurrent matches are running.
-- AI arenas live in a parallel row at Z = 20000 (see AIMatchCoordinator).
local ARENA_Y = 5000
local ARENA_SPACING = 2000

local function cloneArena()
	local template = ServerStorage.ArenaTemplates:FindFirstChild("Arena")
	if not template then return nil end
	local arena = template:Clone()
	nextArenaIndex += 1
	arena.Name = "Arena_" .. nextArenaIndex
	arena:PivotTo(CFrame.new(nextArenaIndex * ARENA_SPACING, ARENA_Y, 0))
	arena.Parent = Workspace
	game:GetService("CollectionService"):AddTag(arena, "DuelArena")
	return arena
end

local function findSpawn(arena, name)
	for _, desc in ipairs(arena:GetDescendants()) do
		if desc.Name == name and desc:IsA("BasePart") then return desc end
	end
	return nil
end

local function freezeCharacter(character, frozen)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if frozen then
		if hum.WalkSpeed > 0 or hum.JumpPower > 0 then
			character:SetAttribute("PreFreezeWalkSpeed", hum.WalkSpeed)
			character:SetAttribute("PreFreezeJumpPower", hum.JumpPower)
		end
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	else
		hum.WalkSpeed = character:GetAttribute("PreFreezeWalkSpeed") or 16
		hum.JumpPower = character:GetAttribute("PreFreezeJumpPower") or 50
		character:SetAttribute("PreFreezeWalkSpeed", nil)
		character:SetAttribute("PreFreezeJumpPower", nil)
	end
end

local function teleportPlayer(player, cframe)
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then hrp.CFrame = cframe + Vector3.new(0, 3, 0) end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("ForceField") then c:Destroy() end
	end
end

local function setHealth(player, amount)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.MaxHealth = amount
		hum.Health = amount
	end
end

local function getHealth(player)
	local char = player.Character
	if not char then return 0 end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health or 0
end

local function awaitAbilityChoices(match)
	local chosen = { [match.p1.UserId] = nil, [match.p2.UserId] = nil }
	local conn
	local done = Instance.new("BindableEvent")

	conn = Remotes.AbilitySelected.OnServerEvent:Connect(function(player, ability)
		if not AbilityDefs.isValid(ability) then return end
		if chosen[player.UserId] == nil and (player == match.p1 or player == match.p2) then
			chosen[player.UserId] = ability
			if chosen[match.p1.UserId] and chosen[match.p2.UserId] then
				done:Fire()
			end
		end
	end)

	local startTime = os.clock()
	task.spawn(function()
		while os.clock() - startTime < GameConfig.AbilitySelectDuration do
			if chosen[match.p1.UserId] and chosen[match.p2.UserId] then return end
			task.wait(0.2)
		end
		done:Fire()
	end)

	done.Event:Wait()
	conn:Disconnect()
	done:Destroy()

	chosen[match.p1.UserId] = chosen[match.p1.UserId] or AbilityDefs.randomAbility()
	chosen[match.p2.UserId] = chosen[match.p2.UserId] or AbilityDefs.randomAbility()
	return chosen
end

local function determineWinner(match)
	local h1 = getHealth(match.p1)
	local h2 = getHealth(match.p2)
	if h1 <= 0 and h2 <= 0 then return "draw" end
	if h1 <= 0 then return "B" end
	if h2 <= 0 then return "A" end
	if h1 > h2 then return "A" end
	if h2 > h1 then return "B" end
	return "draw"
end

local function cleanupMatch(match)
	if match.cleaned then return end
	match.cleaned = true
	for _, player in ipairs({ match.p1, match.p2 }) do
		if CombatService then
			if match.abilities and match.abilities[player.UserId] then
				CombatService.unequipAbility(player, match.abilities[player.UserId])
			end
			CombatService.clearMatchState(player)
		end
		player:SetAttribute("InMatch", false)
		player:SetAttribute("MatchActive", false)
	end
	if match.arena then match.arena:Destroy() end
	activeMatches[match.id] = nil
end

function ArenaManager.startMatch(p1, p2, eloService, lobbySpawnCFrame)
	local match = {
		id = "m_" .. p1.UserId .. "_" .. p2.UserId .. "_" .. os.time(),
		p1 = p1,
		p2 = p2,
		abilities = {},
		active = false,
		deaths = {},
	}
	activeMatches[match.id] = match

	p1:SetAttribute("InMatch", true)
	p2:SetAttribute("InMatch", true)

	local arena = cloneArena()
	if not arena then
		warn("[ArenaManager] Arena template missing")
		cleanupMatch(match)
		return
	end
	match.arena = arena

	local sp1 = findSpawn(arena, "SpawnA")
	local sp2 = findSpawn(arena, "SpawnB")
	if not (sp1 and sp2) then
		warn("[ArenaManager] Arena spawns missing")
		cleanupMatch(match)
		return
	end

	setHealth(p1, GameConfig.StartingHealth)
	setHealth(p2, GameConfig.StartingHealth)
	teleportPlayer(p1, sp1.CFrame)
	teleportPlayer(p2, sp2.CFrame)
	freezeCharacter(p1.Character, true)
	freezeCharacter(p2.Character, true)

	-- Tell the client where the arena is so flying can hard-clamp inside.
	local arenaCenter = arena:GetPivot().Position
	if p1.Character then p1.Character:SetAttribute("ArenaCenter", arenaCenter) end
	if p2.Character then p2.Character:SetAttribute("ArenaCenter", arenaCenter) end

	-- Per-match direct Humanoid.Died hooks. The CombatService eventBus
	-- usually catches deaths, but it relies on matchStates being populated
	-- and on the Died event firing through CombatService.watchDeaths. If
	-- either path drops a frame (e.g. fractional-damage health regen
	-- bouncing back above 0 between polls, or a respawn race), the loop
	-- below would otherwise keep running with the player at ~0 HP. These
	-- direct hooks set match.active = false the instant Died fires.
	local function endOn(p)
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Connect(function() match.active = false end)
		end
		p.CharacterAdded:Connect(function(char)
			local h = char:WaitForChild("Humanoid", 5)
			if h then h.Died:Connect(function() match.active = false end) end
		end)
	end
	endOn(p1)
	endOn(p2)

	local p1Elo = eloService.getElo(p1)
	local p2Elo = eloService.getElo(p2)
	Remotes.ShowAbilitySelection:FireClient(p1, { opponent = p2.DisplayName, opponentElo = p2Elo, selfElo = p1Elo })
	Remotes.ShowAbilitySelection:FireClient(p2, { opponent = p1.DisplayName, opponentElo = p1Elo, selfElo = p2Elo })

	local picks = awaitAbilityChoices(match)
	match.abilities = picks

	if CombatService then
		CombatService.equipAbility(p1, picks[p1.UserId])
		CombatService.equipAbility(p2, picks[p2.UserId])
		CombatService.setMatchState(p1, p2, picks[p1.UserId], false)
		CombatService.setMatchState(p2, p1, picks[p2.UserId], false)
	end
	-- Re-freeze: equipAbility (Super Speed) can raise WalkSpeed during the countdown.
	freezeCharacter(p1.Character, true)
	freezeCharacter(p2.Character, true)

	for i = GameConfig.CountdownDuration, 1, -1 do
		Remotes.MatchCountdown:FireClient(p1, i)
		Remotes.MatchCountdown:FireClient(p2, i)
		task.wait(1)
	end
	Remotes.MatchCountdown:FireClient(p1, 0)
	Remotes.MatchCountdown:FireClient(p2, 0)

	freezeCharacter(p1.Character, false)
	freezeCharacter(p2.Character, false)
	match.active = true
	p1:SetAttribute("MatchActive", true)
	p2:SetAttribute("MatchActive", true)
	if CombatService then
		CombatService.setMatchState(p1, p2, picks[p1.UserId], true)
		CombatService.setMatchState(p2, p1, picks[p2.UserId], true)
	end
	Remotes.MatchStarted:FireClient(p1, { ability = picks[p1.UserId], opponentAbility = picks[p2.UserId] })
	Remotes.MatchStarted:FireClient(p2, { ability = picks[p2.UserId], opponentAbility = picks[p1.UserId] })

	local startT = os.clock()
	local duration = GameConfig.MatchDuration
	while match.active do
		local elapsed = os.clock() - startT
		local remaining = math.max(0, duration - elapsed)
		Remotes.TimerUpdate:FireClient(p1, remaining)
		Remotes.TimerUpdate:FireClient(p2, remaining)

		-- < 1 (not <= 0) so fractional regen can't keep the loop alive
		-- after a kill blow. The direct Died hooks above are the
		-- primary signal; this is belt-and-braces.
		if getHealth(p1) < 1 or getHealth(p2) < 1 then break end
		if remaining <= 0 then break end
		if not (p1.Parent and p2.Parent) then break end
		task.wait(0.25)
	end

	match.active = false
	p1:SetAttribute("MatchActive", false)
	p2:SetAttribute("MatchActive", false)
	if CombatService then
		CombatService.setMatchState(p1, p2, picks[p1.UserId], false)
		CombatService.setMatchState(p2, p1, picks[p2.UserId], false)
	end

	local result
	if not p1.Parent then result = "B"
	elseif not p2.Parent then result = "A"
	else result = determineWinner(match) end

	local dA, dB = 0, 0
	if p1.Parent and p2.Parent then
		dA, dB = eloService.applyResult(p1, p2, result)
	end

	-- Coin rewards. Awarded to whoever's still in the server — disconnect
	-- forfeits forfeit the reward too, otherwise leaving mid-match would
	-- pay out the same as finishing. CurrencyService.add is a no-op for
	-- a player whose state hasn't loaded yet, so this is safe pre-load.
	-- Streak bonus is added on top via applyStreak; both numbers are
	-- captured per-player so the result banner can show the breakdown.
	local p1Coins, p2Coins = 0, 0
	local p1StreakTitle, p1StreakBonus = nil, 0
	local p2StreakTitle, p2StreakBonus = nil, 0
	if p1.Parent then
		p1Coins = result == "draw" and COINS_DRAW
			or (result == "A" and COINS_WIN or COINS_LOSS)
		CurrencyService.add(p1, p1Coins)
		p1StreakTitle, p1StreakBonus = applyStreak(p1, result == "A")
	end
	if p2.Parent then
		p2Coins = result == "draw" and COINS_DRAW
			or (result == "B" and COINS_WIN or COINS_LOSS)
		CurrencyService.add(p2, p2Coins)
		p2StreakTitle, p2StreakBonus = applyStreak(p2, result == "B")
	end

	local function sendEnd(player, delta, opponent, won, coins, streakTitle, streakBonus)
		if not player.Parent then return end
		Remotes.MatchEnded:FireClient(player, {
			result = result,
			won = won,
			draw = result == "draw",
			delta = delta,
			selfHealth = getHealth(player),
			opponentName = opponent.DisplayName,
			opponentHealth = getHealth(opponent),
			newElo = eloService.getElo(player),
			coins = coins,
			streakTitle = streakTitle,
			streakBonus = streakBonus,
		})
	end
	sendEnd(p1, dA, p2, result == "A", p1Coins, p1StreakTitle, p1StreakBonus)
	sendEnd(p2, dB, p1, result == "B", p2Coins, p2StreakTitle, p2StreakBonus)

	task.wait(GameConfig.PostMatchDuration)

	if lobbySpawnCFrame then
		if p1.Parent then teleportPlayer(p1, lobbySpawnCFrame) end
		if p2.Parent then teleportPlayer(p2, lobbySpawnCFrame) end
	end

	setHealth(p1, 100)
	setHealth(p2, 100)

	cleanupMatch(match)
end

function ArenaManager.init(combatService)
	CombatService = combatService
	if combatService and combatService._eventBus then
		combatService._eventBus.Event:Connect(function(event, player)
			if event == "Death" then
				for _, match in pairs(activeMatches) do
					if match.p1 == player or match.p2 == player then
						match.active = false
						break
					end
				end
			end
		end)
	end
	-- Drop the streak entry when a player leaves so the table doesn't
	-- grow with stale UserIds across the server's lifetime.
	Players.PlayerRemoving:Connect(function(player)
		streaks[player.UserId] = nil
	end)
end

return ArenaManager
