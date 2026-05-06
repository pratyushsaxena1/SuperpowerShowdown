-- Magnetism: yank the opponent toward you with a magnetic chain, then
-- deal a one-shot damage hit on contact.
--
-- Implementation note: the previous version did an end-of-pull CFrame
-- teleport when the BV finished out of range. On a player-owned
-- character that's a snap-then-revert (network ownership re-asserts the
-- old position one frame later), causing the visual glitch the user
-- saw. This version drops the teleport entirely and uses a closest-
-- distance tracker — if the opponent got within a forgiving contact
-- threshold AT ANY POINT during the pull, the slam lands. Cleaner and
-- still feels reliable because the BV velocity refreshes each tick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local VFX = require(ReplicatedStorage.SharedModules.VFX)

local Magnetism = {}

Magnetism.cooldown = 6
Magnetism.meleeDamage = 8
Magnetism.speedMultiplier = 1.0
Magnetism.pullDuration = 0.6
Magnetism.pullDamage = 16
-- Generous contact threshold (8 vs the 5–7 we were using) so the hit
-- lands as long as the pull made meaningful progress, not just when the
-- target stops exactly inside punch range.
Magnetism.contactRadius = 8
Magnetism.range = 60
Magnetism.pullSpeed = 120

local CHAIN_COLOR = Color3.fromRGB(255, 200, 80)

function Magnetism.onEquip() end
function Magnetism.onUnequip() end

local function spawnChain(fromPos, toPos)
	local mid = (fromPos + toPos) * 0.5
	local len = (toPos - fromPos).Magnitude
	if len < 0.1 then return end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = CHAIN_COLOR
	p.Size = Vector3.new(0.4, 0.4, len)
	p.CFrame = CFrame.lookAt(mid, toPos)
	p.Transparency = 0.05
	p.Parent = Workspace
	Debris:AddItem(p, 0.5)
	TweenService:Create(p, TweenInfo.new(0.4),
		{ Transparency = 1 }):Play()
end

function Magnetism.onActivate(character, opponent, ctx)
	if not (opponent and opponent.Parent) then return end
	local selfRoot = character:FindFirstChild("HumanoidRootPart")
	local oppRoot = opponent:FindFirstChild("HumanoidRootPart")
	if not (selfRoot and oppRoot) then return end
	if (oppRoot.Position - selfRoot.Position).Magnitude > Magnetism.range then return end

	-- Persistent BodyVelocity refreshed per tick.
	local bv = Instance.new("BodyVelocity")
	bv.Name = "MagnetismPull"
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Velocity = Vector3.new(0, 0, 0)
	bv.Parent = oppRoot

	VFX.sphereBurst(selfRoot.Position + Vector3.new(0, 1, 0), CHAIN_COLOR, 6, 0.4)

	-- Run the pull on a single coroutine. Track closestDist across the
	-- whole window; deal damage the FIRST moment we cross the contact
	-- threshold OR (fallback) at the end if closestDist <= contactRadius.
	task.spawn(function()
		local startTime = os.clock()
		local hit = false
		local closestDist = math.huge
		local lastChain = 0
		while os.clock() - startTime < Magnetism.pullDuration do
			if not (oppRoot.Parent and selfRoot.Parent) then break end
			local toCaster = selfRoot.Position - oppRoot.Position
			local dist = toCaster.Magnitude
			if dist < closestDist then closestDist = dist end

			if not hit and dist <= Magnetism.contactRadius then
				if ctx and ctx.dealDamage then
					ctx.dealDamage(opponent, Magnetism.pullDamage)
				end
				VFX.ring(oppRoot.Position, CHAIN_COLOR, 8, 0.4)
				VFX.sphereBurst(oppRoot.Position + Vector3.new(0, 1, 0),
					CHAIN_COLOR, 5, 0.3)
				hit = true
				-- Don't break — keep the BV running so the opponent gets
				-- a clean visual yank into range, then we let the BV
				-- expire at the end of the loop. Stops the "hit and
				-- nothing happens" feel.
			end

			-- Aim the velocity at the caster's CURRENT position. Lift
			-- a bit so the target doesn't grind on the floor mid-pull.
			local dir = (dist > 0.01) and toCaster.Unit or Vector3.new(0, 0, -1)
			bv.Velocity = dir * Magnetism.pullSpeed + Vector3.new(0, 12, 0)

			if os.clock() - lastChain > 0.06 then
				spawnChain(selfRoot.Position + Vector3.new(0, 1, 0),
					oppRoot.Position + Vector3.new(0, 1, 0))
				lastChain = os.clock()
			end
			task.wait(0.04)
		end

		if bv and bv.Parent then bv:Destroy() end

		-- Fallback: BV finished without crossing contactRadius. If they
		-- got CLOSE (within contactRadius + 4 = 12 studs), still deal
		-- damage so Magnetism doesn't feel like it whiffed when the
		-- target was clearly being yanked. NO teleport — that's the
		-- thing that caused the snap-glitch.
		if not hit and closestDist <= Magnetism.contactRadius + 4
			and oppRoot.Parent and selfRoot.Parent then
			if ctx and ctx.dealDamage then
				ctx.dealDamage(opponent, Magnetism.pullDamage)
			end
			VFX.ring(oppRoot.Position, CHAIN_COLOR, 6, 0.35)
		end
	end)
end

return Magnetism
