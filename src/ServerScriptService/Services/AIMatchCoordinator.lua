local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.SharedModules.GameConfig)
local AbilityDefs = require(ReplicatedStorage.SharedModules.AbilityDefs)
local Remotes = ReplicatedStorage.RemoteEvents

local CurrencyService = require(script.Parent.CurrencyService)

local AIMatchCoordinator = {}
local CombatService
local BotAIController
local arenaCounter = 0

-- AI win pays less than PvP (15 vs 50) so PvP stays the more rewarding
-- path. Losses to bots pay nothing — the training mode is for learning,
-- not farming.
local COINS_AI_WIN = 15

local BOT_NAMES = { "Nova Bot", "Pixel", "Echo", "Titan", "Blaze", "Vortex", "Cipher", "Specter" }

-- AI arenas sit in a parallel row at Z = 20000 so they can never overlap with
-- the PvP row at Z = 0. X is spaced 2000 studs per concurrent AI match.
local AI_ARENA_Y = 5000
local AI_ARENA_Z = 20000
local AI_ARENA_SPACING = 2000

local function cloneArena()
	local template = ServerStorage.ArenaTemplates:FindFirstChild("Arena")
	if not template then return nil end
	local a = template:Clone()
	arenaCounter += 1
	a.Name = "AIArena_" .. arenaCounter
	a:PivotTo(CFrame.new(arenaCounter * AI_ARENA_SPACING, AI_ARENA_Y, AI_ARENA_Z))
	a.Parent = Workspace
	game:GetService("CollectionService"):AddTag(a, "DuelArena")
	return a
end

local function findSpawn(arena, name)
	for _, d in ipairs(arena:GetDescendants()) do
		if d.Name == name and d:IsA("BasePart") then return d end
	end
end

local function freezeChar(char, frozen)
	local h = char and char:FindFirstChildOfClass("Humanoid")
	if not h then return end
	if frozen then
		if h.WalkSpeed > 0 or h.JumpPower > 0 then
			char:SetAttribute("PreFreezeWalkSpeed", h.WalkSpeed)
			char:SetAttribute("PreFreezeJumpPower", h.JumpPower)
		end
		h.WalkSpeed = 0
		h.JumpPower = 0
	else
		h.WalkSpeed = char:GetAttribute("PreFreezeWalkSpeed") or 16
		h.JumpPower = char:GetAttribute("PreFreezeJumpPower") or 50
		char:SetAttribute("PreFreezeWalkSpeed", nil)
		char:SetAttribute("PreFreezeJumpPower", nil)
	end
end

local function setHealth(char, n)
	local h = char and char:FindFirstChildOfClass("Humanoid")
	if h then h.MaxHealth = n; h.Health = n end
end

local function stripForceFields(char)
	if not char then return end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("ForceField") then c:Destroy() end
	end
end

local function awaitPlayerAbility(player)
	local picked
	local done = Instance.new("BindableEvent")
	local conn
	conn = Remotes.AbilitySelected.OnServerEvent:Connect(function(p, a)
		if p == player and not picked and AbilityDefs.isValid(a) then
			picked = a
			done:Fire()
		end
	end)
	task.spawn(function()
		task.wait(GameConfig.AbilitySelectDuration)
		done:Fire()
	end)
	done.Event:Wait()
	conn:Disconnect()
	done:Destroy()
	return picked or AbilityDefs.randomAbility()
end

function AIMatchCoordinator.startMatch(player, eloService, lobbyReturnCFrame)
	if player:GetAttribute("InMatch") then return end
	player:SetAttribute("InMatch", true)

	local arena = cloneArena()
	if not arena then
		player:SetAttribute("InMatch", false)
		return
	end
	local sp1 = findSpawn(arena, "SpawnA")
	local sp2 = findSpawn(arena, "SpawnB")
	if not (sp1 and sp2) then
		arena:Destroy()
		player:SetAttribute("InMatch", false)
		return
	end

	local botElo = math.random(900, 1100)
	local botName = BOT_NAMES[math.random(1, #BOT_NAMES)]
	local bot = BotAIController.spawnBot(botName, botElo, sp2.CFrame)
	if not bot then
		arena:Destroy()
		player:SetAttribute("InMatch", false)
		return
	end

	setHealth(player.Character, GameConfig.StartingHealth)
	if player.Character then
		player.Character:PivotTo(sp1.CFrame + Vector3.new(0, 3, 0))
		stripForceFields(player.Character)
		-- Tell client where the arena center is so flying can hard-clamp
		-- the player inside the arena.
		player.Character:SetAttribute("ArenaCenter", arena:GetPivot().Position)
	end
	BotAIController.teleport(bot, sp2.CFrame)
	freezeChar(player.Character, true)
	BotAIController.freeze(bot, true)

	local selfElo = eloService.getElo(player)
	Remotes.ShowAbilitySelection:FireClient(player, {
		opponent = botName,
		opponentElo = botElo,
		selfElo = selfElo,
	})

	local playerAbility = awaitPlayerAbility(player)
	local botAbility = AbilityDefs.randomBotAbility()

	if CombatService then
		CombatService.equipAbility(player, playerAbility)
		CombatService.setMatchState(player, bot, playerAbility, false)
	end
	BotAIController.equipAbility(bot, botAbility)
	-- Re-freeze: SuperSpeed.onEquip raises WalkSpeed, overriding the earlier freeze.
	freezeChar(player.Character, true)
	BotAIController.freeze(bot, true)

	for i = GameConfig.CountdownDuration, 1, -1 do
		Remotes.MatchCountdown:FireClient(player, i)
		task.wait(1)
	end
	Remotes.MatchCountdown:FireClient(player, 0)

	freezeChar(player.Character, false)
	BotAIController.freeze(bot, false)
	player:SetAttribute("MatchActive", true)
	if CombatService then
		CombatService.setMatchState(player, bot, playerAbility, true)
	end
	Remotes.MatchStarted:FireClient(player, {
		ability = playerAbility,
		opponentAbility = botAbility,
	})

	local stopFlag = { value = false }
	local botHum = bot:FindFirstChildOfClass("Humanoid")

	-- Bots aren't Players, so CombatService.watchDeaths never hooks them.
	-- Wire the bot Humanoid's Died directly so the player's equipped
	-- Kill Effect / Finishing Move plays on the bot's body when it dies.
	if botHum and CombatService and CombatService.playKillCosmetics then
		botHum.Died:Connect(function()
			CombatService.playKillCosmetics(player, bot)
		end)
	end

	local function botDealDamage(dmg)
		if not player.Character then return end
		CombatService.applyDamage(nil, player.Character, dmg, bot)
	end
	local botCtx = {
		dealDamage = function(victim, amount)
			CombatService.applyDamage(nil, victim, amount, bot)
		end,
		healSelf = function(amount)
			CombatService.healCharacter(bot, amount)
		end,
	}
	BotAIController.startAI(bot, player.Character, botAbility, stopFlag, botDealDamage, botCtx)

	task.spawn(function()
		while not stopFlag.value do
			if botHum and botHum.Parent then
				Remotes.HealthUpdate:FireClient(player, {
					target = "opponent",
					health = botHum.Health,
					max = botHum.MaxHealth,
				})
			end
			task.wait(0.3)
		end
	end)

	local startT = os.clock()
	local duration = GameConfig.MatchDuration
	while true do
		local remaining = math.max(0, duration - (os.clock() - startT))
		Remotes.TimerUpdate:FireClient(player, remaining)
		if not player.Parent then break end
		local pHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		-- < 1 (not <= 0) so fractional Humanoid health regen can't keep
		-- the loop alive after a kill blow.
		if not pHum or pHum.Health < 1 then break end
		if not botHum or botHum.Health < 1 then break end
		if remaining <= 0 then break end
		task.wait(0.25)
	end
	stopFlag.value = true
	player:SetAttribute("MatchActive", false)

	local pHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local pHP = pHum and pHum.Health or 0
	local bHP = botHum and botHum.Health or 0
	local result
	if not player.Parent then result = "B"
	elseif pHP <= 0 and bHP <= 0 then result = "draw"
	elseif pHP <= 0 then result = "B"
	elseif bHP <= 0 then result = "A"
	elseif pHP > bHP then result = "A"
	elseif bHP > pHP then result = "B"
	else result = "draw" end

	local coinReward = 0
	if player.Parent and result == "A" then
		coinReward = COINS_AI_WIN
		CurrencyService.add(player, coinReward)
	end

	if player.Parent then
		Remotes.MatchEnded:FireClient(player, {
			result = result,
			won = result == "A",
			draw = result == "draw",
			delta = 0,
			selfHealth = pHP,
			opponentName = botName .. " (AI)",
			opponentHealth = bHP,
			newElo = eloService.getElo(player),
			coins = coinReward,
			-- AI matches don't count toward streaks (PvP-only) so omit
			-- streakTitle / streakBonus.
		})
	end

	task.wait(GameConfig.PostMatchDuration)

	if player.Parent and lobbyReturnCFrame and player.Character then
		player.Character:PivotTo(lobbyReturnCFrame + Vector3.new(0, 3, 0))
	end
	setHealth(player.Character, 100)

	if CombatService then
		CombatService.unequipAbility(player, playerAbility)
		CombatService.clearMatchState(player)
	end
	BotAIController.despawn(bot)
	if arena and arena.Parent then arena:Destroy() end
	player:SetAttribute("InMatch", false)
end

function AIMatchCoordinator.init(combatService, botAI)
	CombatService = combatService
	BotAIController = botAI
end

return AIMatchCoordinator
