local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.SharedModules.GameConfig)
local AbilityDefs = require(ReplicatedStorage.SharedModules.AbilityDefs)

local Abilities = ReplicatedStorage.Abilities
local Remotes = ReplicatedStorage.RemoteEvents

local CombatService = {}

local lastAttack = {}
local lastAbility = {}
local matchStates = {}

-- Optional cosmetics dependency (kill effects + finishing moves). Injected
-- via init so this module still loads and runs without it.
local CosmeticsService
local KillEffectsCatalog = require(ReplicatedStorage.SharedModules.KillEffectsCatalog)
local FinishingMovesCatalog = require(ReplicatedStorage.SharedModules.FinishingMovesCatalog)

local function getAbilityModule(name)
	local mod = Abilities:FindFirstChild(name)
	return mod and require(mod) or nil
end

local function resolveOpponentChar(st)
	if st.opponentCharacter and st.opponentCharacter.Parent then
		return st.opponentCharacter
	end
	if st.opponentUserId then
		local p = Players:GetPlayerByUserId(st.opponentUserId)
		return p and p.Character or nil
	end
end

function CombatService.setMatchState(player, opponentRef, ability, active)
	local opponentUserId, opponentCharacter
	if typeof(opponentRef) == "Instance" then
		if opponentRef:IsA("Player") then
			opponentUserId = opponentRef.UserId
			opponentCharacter = opponentRef.Character
		elseif opponentRef:IsA("Model") then
			opponentCharacter = opponentRef
		end
	end
	matchStates[player.UserId] = {
		opponentUserId = opponentUserId,
		opponentCharacter = opponentCharacter,
		ability = ability,
		active = active and true or false,
	}
end

function CombatService.clearMatchState(player)
	matchStates[player.UserId] = nil
	lastAttack[player.UserId] = nil
	lastAbility[player.UserId] = nil
end

function CombatService.equipAbility(player, abilityName)
	if not player.Character then return end
	local mod = getAbilityModule(abilityName)
	if mod and mod.onEquip then mod.onEquip(player.Character) end
end

function CombatService.unequipAbility(player, abilityName)
	if not player.Character or not abilityName then return end
	local mod = getAbilityModule(abilityName)
	if mod and mod.onUnequip then mod.onUnequip(player.Character) end
end

local function applyDamage(attackerPlayer, victimChar, damage, attackerChar)
	if not victimChar or not victimChar.Parent then return end
	local hum = victimChar:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	if not attackerChar and attackerPlayer then attackerChar = attackerPlayer.Character end
	local outMul = (attackerChar and attackerChar:GetAttribute("DamageMultiplier")) or 1
	local inMul = (victimChar:GetAttribute("IncomingDamageMultiplier")) or 1
	damage = damage * outMul * inMul

	-- Mirror: if the victim has an active reflect window AND the attacker
	-- is a different character (so reflected damage doesn't hit the
	-- mirroring player itself when they self-damage somehow), redirect
	-- the entire blow to the attacker. Skip the standard victim damage
	-- path entirely so the same hit can't be applied twice.
	if attackerChar and attackerChar ~= victimChar
		and victimChar:GetAttribute("Mirroring") == true
		and (victimChar:GetAttribute("MirrorEnds") or 0) > os.clock() then
		local atkHum = attackerChar:FindFirstChildOfClass("Humanoid")
		if atkHum and atkHum.Health > 0 then
			-- Recursive call would re-mirror if the attacker is also
			-- mirroring; both windows cancel and no one takes damage.
			-- That's a fine edge case — keeps the math simple.
			atkHum:TakeDamage(damage)
			if atkHum.Health < 0 then atkHum.Health = 0 end
			local atkPlayer = Players:GetPlayerFromCharacter(attackerChar)
			local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
			local h = math.max(0, atkHum.Health)
			if atkPlayer then
				Remotes.HealthUpdate:FireClient(atkPlayer, { target = "self", health = h, max = atkHum.MaxHealth })
			end
			if victimPlayer then
				Remotes.HealthUpdate:FireClient(victimPlayer, { target = "opponent", health = h, max = atkHum.MaxHealth })
			end
			Remotes.DamageNumber:FireAllClients(attackerChar, damage)
		end
		return
	end

	local invis = getAbilityModule("Invisibility")
	if invis and invis.onHit then invis.onHit(victimChar) end

	hum:TakeDamage(damage)
	-- Defensive clamp: TakeDamage already floors at 0, but a stray negative
	-- damage value or post-hook mutation could leave Health below zero, so
	-- pin it before broadcasting.
	if hum.Health < 0 then hum.Health = 0 end
	local reportedHealth = math.max(0, hum.Health)
	if attackerPlayer then
		Remotes.HealthUpdate:FireClient(attackerPlayer, { target = "opponent", health = reportedHealth, max = hum.MaxHealth })
	end
	local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
	if victimPlayer then
		Remotes.HealthUpdate:FireClient(victimPlayer, { target = "self", health = reportedHealth, max = hum.MaxHealth })
	end
	Remotes.DamageNumber:FireAllClients(victimChar, damage)
end

CombatService.applyDamage = applyDamage

local function healCharacter(char, amount)
	if not char or not char.Parent then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local newHealth = math.min(hum.MaxHealth, hum.Health + amount)
	hum.Health = newHealth
	local p = Players:GetPlayerFromCharacter(char)
	if p then
		Remotes.HealthUpdate:FireClient(p, { target = "self", health = hum.Health, max = hum.MaxHealth })
	end
	local st = p and matchStates[p.UserId]
	if st and st.opponentUserId then
		local op = Players:GetPlayerByUserId(st.opponentUserId)
		if op then
			Remotes.HealthUpdate:FireClient(op, { target = "opponent", health = hum.Health, max = hum.MaxHealth })
		end
	end
end

CombatService.healCharacter = healCharacter

-- Client-authoritative punch visual: each client tweens the attacker's shoulder
-- locally on receipt of AbilityEffect, so there's no server→client replication
-- delay. CombatService.playPunchAnim is deliberately a no-op (retained so
-- BotAIController can call it without breaking).
local function playPunchAnim() end
CombatService.playPunchAnim = playPunchAnim

local function buildCtx(attackerPlayer, char)
	return {
		dealDamage = function(victim, amount)
			applyDamage(attackerPlayer, victim, amount, char)
		end,
		healSelf = function(amount)
			healCharacter(char, amount)
		end,
		applyDamage = function(attacker, victim, amount)
			applyDamage(attacker or attackerPlayer, victim, amount, char)
		end,
	}
end

CombatService.buildCtx = buildCtx

local function onAttack(player)
	local st = matchStates[player.UserId]
	if not st or not st.active then return end
	local now = os.clock()
	local baseCD = GameConfig.BasicAttackCooldown
	local mod = st.ability and getAbilityModule(st.ability)
	if mod and mod.speedMultiplier and mod.speedMultiplier > 1 then
		baseCD = baseCD / mod.speedMultiplier
	end
	if lastAttack[player.UserId] and now - lastAttack[player.UserId] < baseCD then return end
	lastAttack[player.UserId] = now

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Swinging ALWAYS plays the punch (cooldown-gated above). Damage only
	-- lands if the opponent is in range; the swing animation still fires
	-- either way so the input feels responsive.
	local invisMod = getAbilityModule("Invisibility")
	if invisMod and invisMod.onAttack then invisMod.onAttack(char) end

	-- Target selection: the opponent is the primary target, but tagged
	-- Duplication decoys are also hittable so the player can clear them out.
	-- Pick the nearest in-range humanoid of those candidates.
	local candidates = {}
	local opponentChar = resolveOpponentChar(st)
	if opponentChar then table.insert(candidates, opponentChar) end
	for _, decoy in ipairs(CollectionService:GetTagged("Decoy")) do
		if decoy ~= char and decoy.Parent then table.insert(candidates, decoy) end
	end

	local bestTarget, bestDist
	for _, cand in ipairs(candidates) do
		local cRoot = cand:FindFirstChild("HumanoidRootPart") or cand:FindFirstChild("Torso")
		if cRoot then
			local d = (cRoot.Position - root.Position).Magnitude
			if d <= GameConfig.BasicAttackRange and (not bestDist or d < bestDist) then
				bestTarget = cand
				bestDist = d
			end
		end
	end

	local didHit = false
	if bestTarget then
		local dmg = GameConfig.BasicAttackDamage
		if mod and mod.meleeDamage then dmg = mod.meleeDamage end
		applyDamage(player, bestTarget, dmg, char)
		didHit = true
	end

	Remotes.AbilityEffect:FireAllClients({
		kind = "melee",
		from = char,
		to = didHit and bestTarget or nil,
	})
end

local function onAbility(player, aimDir)
	local st = matchStates[player.UserId]
	if not st or not st.active or not st.ability then return end
	local mod = getAbilityModule(st.ability)
	if not mod then return end
	local cd = mod.cooldown or 0
	if cd > 0 then
		local now = os.clock()
		if lastAbility[player.UserId] and now - lastAbility[player.UserId] < cd then return end
		lastAbility[player.UserId] = now
	end
	local char = player.Character
	if not char then return end

	local opponentChar = resolveOpponentChar(st)
	local ctx = buildCtx(player, char)
	-- Client sends the camera LookVector so aim-sensitive abilities
	-- (Teleportation) can act along a 3D direction, not just XZ.
	if typeof(aimDir) == "Vector3" and aimDir.Magnitude > 0.01 then
		ctx.aimDir = aimDir.Unit
	end
	if mod.onActivate then mod.onActivate(char, opponentChar, ctx) end

	Remotes.AbilityEffect:FireAllClients({ kind = "ability", ability = st.ability, from = char })
end

-- Apply the killer's equipped Kill Effect + Finishing Move to the victim.
-- Pulled out so AIMatchCoordinator can call the same path when a bot is
-- killed (bots aren't watched by CombatService.watchDeaths).
function CombatService.playKillCosmetics(killerPlayer, victimChar)
	if not CosmeticsService then return end
	if not killerPlayer or not victimChar then return end
	local effect = CosmeticsService.equipped(killerPlayer, "killEffects")
	if effect ~= "" then
		pcall(KillEffectsCatalog.apply, victimChar, effect)
	end
	local move = CosmeticsService.equipped(killerPlayer, "finishingMoves")
	if move ~= "" then
		pcall(FinishingMovesCatalog.apply, victimChar, move)
	end
end

local function onDeath(player)
	local st = matchStates[player.UserId]
	if not st then return end

	-- Resolve the killer from the victim's match state. In PvP this is the
	-- opposing Player; in AI matches it's a bot Model with no Player and
	-- thus no equipped cosmetics — playKillCosmetics no-ops on nil.
	local killerPlayer
	if st.opponentUserId then
		killerPlayer = Players:GetPlayerByUserId(st.opponentUserId)
	end
	if killerPlayer and player.Character then
		CombatService.playKillCosmetics(killerPlayer, player.Character)
	end

	local eventBus = CombatService._eventBus
	if eventBus then eventBus:Fire("Death", player, killerPlayer) end
end

function CombatService.watchDeaths(player)
	local function hook(char)
		local hum = char:WaitForChild("Humanoid", 5)
		if not hum then return end
		hum.Died:Connect(function() onDeath(player) end)
	end
	if player.Character then hook(player.Character) end
	player.CharacterAdded:Connect(hook)
end

function CombatService.init(eventBus, cosmeticsService)
	CombatService._eventBus = eventBus
	CosmeticsService = cosmeticsService
	Remotes.RequestBasicAttack.OnServerEvent:Connect(onAttack)
	Remotes.RequestAbilityActivation.OnServerEvent:Connect(onAbility)
	Players.PlayerAdded:Connect(CombatService.watchDeaths)
	for _, p in ipairs(Players:GetPlayers()) do CombatService.watchDeaths(p) end
end

return CombatService
