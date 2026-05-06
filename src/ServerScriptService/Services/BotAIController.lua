local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.SharedModules.GameConfig)
local Remotes = ReplicatedStorage.RemoteEvents
local Abilities = ReplicatedStorage.Abilities

local CombatService -- lazy-required to avoid circular require
local function getCombatService()
	if not CombatService then
		CombatService = require(script.Parent:WaitForChild("CombatService"))
	end
	return CombatService
end

local BotAIController = {}
local botCounter = 0

-- Bot nametags intentionally left off — opponents shouldn't have a name+Elo
-- billboard floating above their head during a fight. The HUD's "OPPONENT"
-- HP bar is the only opponent UI during combat.
local function attachNametag(_, _) end

function BotAIController.spawnBot(name, elo, initialCFrame)
	botCounter += 1
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[BotAI] Failed to create humanoid model: " .. tostring(model))
		return nil
	end
	model.Name = name or ("Bot_" .. botCounter)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.MaxHealth = GameConfig.StartingHealth
		hum.Health = GameConfig.StartingHealth
		hum.DisplayName = model.Name
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	-- Pivot BEFORE parenting so the bot never flashes at world origin
	-- (which lives inside the lobby bounding box).
	if initialCFrame then
		model:PivotTo(initialCFrame + Vector3.new(0, 3, 0))
	else
		model:PivotTo(CFrame.new(0, -5000, 0))
	end
	model.Parent = Workspace
	attachNametag(model, elo)
	return model
end

function BotAIController.teleport(bot, cframe)
	if not bot or not bot.Parent then return end
	bot:PivotTo(cframe + Vector3.new(0, 3, 0))
	for _, c in ipairs(bot:GetChildren()) do
		if c:IsA("ForceField") then c:Destroy() end
	end
end

function BotAIController.freeze(bot, frozen)
	if not bot then return end
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if frozen then
		if hum.WalkSpeed > 0 or hum.JumpPower > 0 then
			bot:SetAttribute("PreFreezeWalkSpeed", hum.WalkSpeed)
			bot:SetAttribute("PreFreezeJumpPower", hum.JumpPower)
		end
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	else
		hum.WalkSpeed = bot:GetAttribute("PreFreezeWalkSpeed") or 16
		hum.JumpPower = bot:GetAttribute("PreFreezeJumpPower") or 50
		bot:SetAttribute("PreFreezeWalkSpeed", nil)
		bot:SetAttribute("PreFreezeJumpPower", nil)
	end
end

function BotAIController.equipAbility(bot, abilityName)
	local mod = Abilities:FindFirstChild(abilityName)
	if mod then
		local m = require(mod)
		if m.onEquip then m.onEquip(bot) end
	end
end

function BotAIController.unequipAbility(bot, abilityName)
	if not bot or not abilityName then return end
	local mod = Abilities:FindFirstChild(abilityName)
	if mod then
		local m = require(mod)
		if m.onUnequip then m.onUnequip(bot) end
	end
end

-- Orients the bot's HumanoidRootPart toward a target on the XZ plane so
-- the bot always faces the opponent while punching or standing still.
-- We set CFrame directly (not AlignOrientation) because a stopped humanoid
-- doesn't auto-turn; MoveTo turns only while actively walking.
local function faceTarget(bRoot, targetPos)
	local flat = Vector3.new(targetPos.X - bRoot.Position.X, 0, targetPos.Z - bRoot.Position.Z)
	if flat.Magnitude < 0.05 then return end
	local look = flat.Unit
	bRoot.CFrame = CFrame.lookAt(bRoot.Position, bRoot.Position + look)
end

-- Abilities that need the opponent's live position to aim (LightningStrike
-- already no-ops on invisible targets, but for these we skip activation
-- entirely during wander so the bot doesn't burn cooldowns blind).
local OPPONENT_AIMED = {
	LightningStrike = true,
}

function BotAIController.startAI(bot, opponentChar, ability, stopFlag, onDealDamage, botCtx)
	local mod = Abilities:FindFirstChild(ability)
	local abilityMod = mod and require(mod) or nil
	local lastAttack = 0
	local lastAbility = 0
	local lastJump = 0
	local wanderTarget
	local wanderRetargetAt = 0
	task.spawn(function()
		while not stopFlag.value do
			if not (bot.Parent and opponentChar.Parent) then break end
			local hum = bot:FindFirstChildOfClass("Humanoid")
			local oHum = opponentChar:FindFirstChildOfClass("Humanoid")
			local bRoot = bot:FindFirstChild("HumanoidRootPart")
			local oRoot = opponentChar:FindFirstChild("HumanoidRootPart")
			if not (hum and oHum and bRoot and oRoot) then break end
			if hum.Health <= 0 or oHum.Health <= 0 then break end

			local dist = (oRoot.Position - bRoot.Position).Magnitude
			local now = os.clock()

			local opponentInvisible = opponentChar:GetAttribute("IsInvisible") == true

			if opponentInvisible then
				if not wanderTarget or now >= wanderRetargetAt
					or (bRoot.Position - wanderTarget).Magnitude < 3 then
					local angle = math.random() * 2 * math.pi
					local dist2 = 6 + math.random() * 14
					wanderTarget = bRoot.Position + Vector3.new(
						math.cos(angle) * dist2, 0, math.sin(angle) * dist2
					)
					wanderRetargetAt = now + 1.2 + math.random() * 0.8
				end
				hum:MoveTo(wanderTarget)
			else
				wanderTarget = nil
				if dist > 6 then
					hum:MoveTo(oRoot.Position)
					if dist < 12 and now - lastJump > 2 and math.random() < 0.2 then
						lastJump = now
						hum.Jump = true
					end
				else
					-- Cleanly stop without the MoveTo(self) jitter that caused
					-- start/stop animation flicker on every tick.
					hum:Move(Vector3.new(0, 0, 0), false)
					faceTarget(bRoot, oRoot.Position)
					local atkCD = GameConfig.BasicAttackCooldown
					if abilityMod and abilityMod.speedMultiplier and abilityMod.speedMultiplier > 1 then
						atkCD = atkCD / abilityMod.speedMultiplier
					end
					if now - lastAttack > atkCD then
						lastAttack = now
						local dmg = (abilityMod and abilityMod.meleeDamage) or GameConfig.BasicAttackDamage
						onDealDamage(dmg)
						Remotes.AbilityEffect:FireAllClients({ kind = "melee", from = bot, to = opponentChar })
					end
				end
			end

			-- Ability activation runs on both visible + invisible branches so
			-- the bot can still Heal / Shockwave / Flying / SizeShift / etc.
			-- while hunting an invisible opponent. Aimed abilities (Lightning)
			-- opt out during wander so they don't fizzle and waste cooldowns.
			if abilityMod and abilityMod.onActivate and abilityMod.cooldown and not abilityMod.clientOnly then
				local cd = abilityMod.cooldown
				local canAim = not opponentInvisible or not OPPONENT_AIMED[ability]
				local rangeOk = ability == "Healing" or ability == "Invisibility"
					or ability == "SuperSpeed" or ability == "Flying"
					or ability == "SizeShift" or ability == "Duplication"
					or ability == "Mirror"
					or dist < 40
				if now - lastAbility > cd and rangeOk and canAim then
					lastAbility = now
					abilityMod.onActivate(bot, opponentChar, botCtx)
					Remotes.AbilityEffect:FireAllClients({ kind = "ability", ability = ability, from = bot })
				end
			end

			task.wait(0.2)
		end
	end)
end

function BotAIController.playPunch(bot)
	getCombatService().playPunchAnim(bot)
end

function BotAIController.despawn(bot)
	if bot and bot.Parent then bot:Destroy() end
end

return BotAIController
