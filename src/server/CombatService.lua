local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CombatService = {}
CombatService.__index = CombatService

function CombatService.new(deps)
	local self = setmetatable({}, CombatService)
	self._effects     = deps and deps.effects or nil
	self._hp          = {}    -- [player] = number
	self._lastPunch   = {}    -- [player] = tick
	self._inMatch     = {}    -- [player] = true
	self._abilities   = {}    -- [player] = ability module
	self._frozen      = {}    -- [player] = expireTick
	self._invuln      = {}    -- [player] = expireTick
	self._dotJobs     = {}    -- [player] = job id (incremented to invalidate)
	self._dotCounter  = 0
	self._onDeath     = nil
	return self
end

function CombatService:SetOnDeath(cb) self._onDeath = cb end

function CombatService:RegisterMatchPlayer(player, ability)
	self._hp[player] = Config.MAX_HP
	self._inMatch[player] = true
	self._abilities[player] = ability
	self._frozen[player] = nil
	self._invuln[player] = nil
	Remotes.HpUpdated:FireClient(player, Config.MAX_HP, Config.MAX_HP)
end

function CombatService:UnregisterMatchPlayer(player)
	self._hp[player] = nil
	self._inMatch[player] = nil
	self._abilities[player] = nil
	self._frozen[player] = nil
	self._invuln[player] = nil
	self._dotJobs[player] = (self._dotJobs[player] or 0) + 1
	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 16
			hum.JumpHeight = 7.2
			hum.PlatformStand = false
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local lift = root:FindFirstChild("TKLift")
			if lift then lift:Destroy() end
		end
	end
end

function CombatService:GetHP(player) return self._hp[player] end

function CombatService:IsInMatch(player) return self._inMatch[player] == true end

function CombatService:IsFrozen(player)
	local until_ = self._frozen[player]
	return until_ ~= nil and tick() < until_
end

function CombatService:IsInvuln(player)
	local until_ = self._invuln[player]
	return until_ ~= nil and tick() < until_
end

function CombatService:DealDamage(target, amount, source)
	if not self._inMatch[target] then return end
	if self:IsInvuln(target) then return end
	if amount <= 0 then return end
	local cur = self._hp[target] or 0
	cur = math.max(0, cur - amount)
	self._hp[target] = cur
	Remotes.HpUpdated:FireClient(target, cur, Config.MAX_HP)

	-- Roblox Humanoid mirror so character death is visually consistent.
	local char = target.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = math.max(1, (cur / Config.MAX_HP) * hum.MaxHealth)
		end
	end

	-- Hit feedback: target gets a screen flash + shake; source gets a damage number.
	if self._effects then
		self._effects:HitFeedback(target, "hurt", { amount = amount })
		if source then
			self._effects:HitFeedback(source, "hit", { amount = amount, target = target.Name })
		end
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			self._effects:Broadcast("damageNumber", {
				pos = root.Position + Vector3.new(0, 3, 0),
				amount = math.floor(amount + 0.5),
			})
		end
	end

	if cur <= 0 and self._onDeath then
		self._inMatch[target] = nil
		self._onDeath(target, source)
	end
end

function CombatService:Heal(target, amount)
	if not self._inMatch[target] then return end
	local cur = self._hp[target] or 0
	cur = math.min(Config.MAX_HP, cur + amount)
	self._hp[target] = cur
	Remotes.HpUpdated:FireClient(target, cur, Config.MAX_HP)
	local char = target.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.Health = (cur / Config.MAX_HP) * hum.MaxHealth end
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

function CombatService:GetOpponent(player)
	for plr, _ in pairs(self._inMatch) do
		if plr ~= player then return plr end
	end
end

function CombatService:HandlePunch(attacker)
	if not self._inMatch[attacker] then return end
	if self:IsFrozen(attacker) then return end
	local now = tick()
	local last = self._lastPunch[attacker] or 0
	if now - last < Config.PUNCH_COOLDOWN then return end
	self._lastPunch[attacker] = now

	local target = getOpponentInRange(self, attacker, Config.PUNCH_RANGE)
	if not target then return end

	local mult = 1.0
	local ab = self._abilities[attacker]
	if ab and ab.PunchDamageMultiplier then mult = ab.PunchDamageMultiplier end

	-- Punch VFX (broadcast).
	if self._effects then
		local achar = attacker.Character
		local aroot = achar and achar:FindFirstChild("HumanoidRootPart")
		local tchar = target.Character
		local troot = tchar and tchar:FindFirstChild("HumanoidRootPart")
		if aroot and troot then
			self._effects:Broadcast("punch", {
				from = aroot.Position,
				to = troot.Position,
			})
		end
	end

	self:DealDamage(target, Config.BASE_PUNCH_DAMAGE * mult, attacker)
end

function CombatService:HandleSlam(attacker, origin, radius, damage)
	if not self._inMatch[attacker] then return end
	if self._effects then
		self._effects:Broadcast("slam", { pos = origin, radius = radius })
	end
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

-- Status effects ------------------------------------------------------------

function CombatService:Freeze(target, duration)
	if not self._inMatch[target] then return end
	self._frozen[target] = tick() + duration
	local char = target.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = 0 hum.JumpHeight = 0 end
	if self._effects then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			self._effects:Broadcast("freeze", { pos = root.Position, duration = duration })
		end
	end
	task.delay(duration, function()
		if not self._inMatch[target] then return end
		if (self._frozen[target] or 0) > tick() then return end
		self._frozen[target] = nil
		local c = target.Character
		if c then
			local h = c:FindFirstChildOfClass("Humanoid")
			if h then h.WalkSpeed = 16 h.JumpHeight = 7.2 end
		end
	end)
end

function CombatService:GrantInvuln(target, duration)
	self._invuln[target] = tick() + duration
end

function CombatService:ApplyDOT(target, source, perTick, ticks, interval)
	if not self._inMatch[target] then return end
	self._dotCounter += 1
	local job = self._dotCounter
	self._dotJobs[target] = job
	task.spawn(function()
		for _ = 1, ticks do
			task.wait(interval)
			if self._dotJobs[target] ~= job then return end
			if not self._inMatch[target] then return end
			self:DealDamage(target, perTick, source)
		end
	end)
	if self._effects then
		local char = target.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			self._effects:Broadcast("burn", { pos = root.Position, duration = ticks * interval })
		end
	end
end

-- Lift target into the air for a duration, then drop and damage on impact.
function CombatService:Lift(attacker, target, duration, dmg)
	if not self._inMatch[target] then return end
	local char = target.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.PlatformStand = true end

	local av = Instance.new("BodyVelocity")
	av.Name = "TKLift"
	av.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	av.Velocity = Vector3.new(0, 28, 0)
	av.Parent = root
	Debris:AddItem(av, duration)

	if self._effects then
		self._effects:Broadcast("lift", { pos = root.Position, duration = duration })
	end

	task.delay(duration, function()
		if hum and hum.Parent then hum.PlatformStand = false end
		if root and root.Parent then
			root.AssemblyLinearVelocity = Vector3.new(0, -120, 0)
		end
		task.wait(0.25)
		self:DealDamage(target, dmg, attacker)
	end)
end

-- Fire a projectile from origin toward direction, dealing dmg on first opponent hit
-- within range. onHit (optional) gets called with (target) for follow-on effects.
function CombatService:FireProjectile(attacker, origin, direction, opts)
	if not self._inMatch[attacker] then return end
	opts = opts or {}
	local kind = opts.kind or "fireball"
	local speed = opts.speed or 90
	local dmg = opts.damage or 25
	local maxRange = opts.range or 90
	local hitRadius = opts.hitRadius or 4

	local dir = direction.Unit
	local lifetime = maxRange / speed
	if self._effects then
		self._effects:Broadcast(kind, {
			origin = origin, direction = dir, speed = speed, lifetime = lifetime,
		})
	end

	-- Server tick advances the projectile and checks for hits.
	task.spawn(function()
		local elapsed = 0
		local hitOne = false
		local stepHz = 30
		local dt = 1 / stepHz
		while elapsed < lifetime and not hitOne do
			task.wait(dt)
			elapsed += dt
			local pos = origin + dir * speed * elapsed
			for plr, _ in pairs(self._inMatch) do
				if plr ~= attacker then
					local oc = plr.Character
					local oroot = oc and oc:FindFirstChild("HumanoidRootPart")
					if oroot and (oroot.Position - pos).Magnitude <= hitRadius then
						self:DealDamage(plr, dmg, attacker)
						if opts.onHit then opts.onHit(plr) end
						hitOne = true
						break
					end
				end
			end
		end
	end)
end

-- Instant chain bolt: snap to nearest opponent within range, damage, broadcast vfx.
function CombatService:Lightning(attacker, dmg, range)
	if not self._inMatch[attacker] then return end
	local target = getOpponentInRange(self, attacker, range)
	if not target then return end
	local achar = attacker.Character
	local tchar = target.Character
	local aroot = achar and achar:FindFirstChild("HumanoidRootPart")
	local troot = tchar and tchar:FindFirstChild("HumanoidRootPart")
	if not (aroot and troot) then return end
	if self._effects then
		self._effects:Broadcast("lightning", { from = aroot.Position, to = troot.Position })
	end
	self:DealDamage(target, dmg, attacker)
end

-- Dash forward; deals damage to anyone in the swept tube. Brief invuln during dash.
function CombatService:Dash(attacker, distance, dmg, opts)
	if not self._inMatch[attacker] then return end
	opts = opts or {}
	local char = attacker.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local startPos = root.Position
	local dir = root.CFrame.LookVector
	local target = startPos + dir * distance + Vector3.new(0, 1, 0)

	local invuln = opts.invuln or 0.45
	if invuln > 0 then self:GrantInvuln(attacker, invuln) end

	if self._effects then
		self._effects:Broadcast(opts.kind or "shadowDash", { from = startPos, to = target })
	end

	-- Snap to target. Trying to tween server-side fights with client character control;
	-- the broadcast trail VFX sells the motion.
	root.CFrame = CFrame.new(target, target + dir)

	-- Damage anyone close to the path.
	local sweepRadius = opts.sweepRadius or 6
	for plr, _ in pairs(self._inMatch) do
		if plr ~= attacker then
			local oc = plr.Character
			local oroot = oc and oc:FindFirstChild("HumanoidRootPart")
			if oroot then
				local toLine = oroot.Position - startPos
				local along = math.clamp(toLine:Dot(dir), 0, distance)
				local closest = startPos + dir * along
				if (oroot.Position - closest).Magnitude <= sweepRadius then
					self:DealDamage(plr, dmg, attacker)
				end
			end
		end
	end
end

return CombatService
