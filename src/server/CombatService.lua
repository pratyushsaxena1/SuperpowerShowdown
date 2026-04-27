local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CombatService = {}
CombatService.__index = CombatService

function CombatService.new()
	local self = setmetatable({}, CombatService)
	self._hp = {}            -- [player] = number
	self._lastPunch = {}     -- [player] = tick timestamp
	self._inMatch = {}       -- [player] = true
	self._abilities = {}     -- [player] = ability module
	self._onDeath = nil
	return self
end

function CombatService:SetOnDeath(cb) self._onDeath = cb end

function CombatService:RegisterMatchPlayer(player, ability)
	self._hp[player] = Config.MAX_HP
	self._inMatch[player] = true
	self._abilities[player] = ability
	Remotes.HpUpdated:FireClient(player, Config.MAX_HP, Config.MAX_HP)
end

function CombatService:UnregisterMatchPlayer(player)
	self._hp[player] = nil
	self._inMatch[player] = nil
	self._abilities[player] = nil
end

function CombatService:GetHP(player) return self._hp[player] end

function CombatService:DealDamage(target, amount, source)
	if not self._inMatch[target] then return end
	local cur = self._hp[target] or 0
	cur = math.max(0, cur - amount)
	self._hp[target] = cur
	Remotes.HpUpdated:FireClient(target, cur, Config.MAX_HP)
	local char = target.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = math.max(1, (cur / Config.MAX_HP) * hum.MaxHealth)
		end
	end
	if cur <= 0 and self._onDeath then
		self._inMatch[target] = nil
		self._onDeath(target, source)
	end
end

local function getOpponentInRange(self, attacker, range)
	local char = attacker.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local best, bestDist = nil, range
	for plr, _ in pairs(self._inMatch) do
		if plr ~= attacker then
			local oc = plr.Character
			local oroot = oc and oc:FindFirstChild("HumanoidRootPart")
			if oroot then
				local d = (oroot.Position - root.Position).Magnitude
				if d <= bestDist then
					best, bestDist = plr, d
				end
			end
		end
	end
	return best
end

function CombatService:HandlePunch(attacker)
	if not self._inMatch[attacker] then return end
	local now = tick()
	local last = self._lastPunch[attacker] or 0
	if now - last < Config.PUNCH_COOLDOWN then return end
	self._lastPunch[attacker] = now

	local target = getOpponentInRange(self, attacker, Config.PUNCH_RANGE)
	if not target then return end

	local mult = 1.0
	local ab = self._abilities[attacker]
	if ab and ab.PunchDamageMultiplier then mult = ab.PunchDamageMultiplier end
	self:DealDamage(target, Config.BASE_PUNCH_DAMAGE * mult, attacker)
end

function CombatService:HandleSlam(attacker, origin, radius, damage)
	if not self._inMatch[attacker] then return end
	for plr, _ in pairs(self._inMatch) do
		if plr ~= attacker then
			local oc = plr.Character
			local oroot = oc and oc:FindFirstChild("HumanoidRootPart")
			if oroot and (oroot.Position - origin).Magnitude <= radius then
				self:DealDamage(plr, damage, attacker)
				oroot.AssemblyLinearVelocity = (oroot.Position - origin).Unit * 60 + Vector3.new(0, 40, 0)
			end
		end
	end
end

return CombatService
