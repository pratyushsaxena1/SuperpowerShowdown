-- Magnetism: yank the opponent's body toward you with a magnetic chain,
-- then deal a one-shot damage hit on contact. Strong "anti-cover" tool —
-- pulls a hiding opponent out from behind a crate.
--
-- Implementation note: a single static BodyVelocity is unreliable here
-- because (a) the opponent's WASD input fights the velocity vector, and
-- (b) once they pass the caster, the static pull vector keeps shoving
-- them in the wrong direction. We refresh the velocity vector each tick
-- so the pull always points at the caster's current position, and at the
-- end of the pull window we snap them into contact range so the damage
-- always lands even if they got blocked by geometry.

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
Magnetism.contactRadius = 7
Magnetism.range = 60
Magnetism.pullSpeed = 110

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
	Debris:AddItem(p, 0.6)
	TweenService:Create(p, TweenInfo.new(0.5),
		{ Transparency = 1 }):Play()
end

function Magnetism.onActivate(character, opponent, ctx)
	if not (opponent and opponent.Parent) then return end
	local selfRoot = character:FindFirstChild("HumanoidRootPart")
	local oppRoot = opponent:FindFirstChild("HumanoidRootPart")
	if not (selfRoot and oppRoot) then return end
	if (oppRoot.Position - selfRoot.Position).Magnitude > Magnetism.range then return end

	-- Persistent BodyVelocity refreshed per tick. MaxForce huge so it
	-- consistently overrides the opponent's input/gravity.
	local bv = Instance.new("BodyVelocity")
	bv.Name = "MagnetismPull"
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Velocity = Vector3.new(0, 0, 0)
	bv.Parent = oppRoot

	VFX.sphereBurst(selfRoot.Position + Vector3.new(0, 1, 0), CHAIN_COLOR, 6, 0.4)

	local startTime = os.clock()
	local hit = false

	-- Refresh the pull vector + spawn a chain segment at fixed cadence.
	-- Both run on the same tick loop so they stay in sync, and the loop
	-- cleans itself up via the elapsed-time check.
	task.spawn(function()
		local lastChain = 0
		while not hit and os.clock() - startTime < Magnetism.pullDuration do
			if not (oppRoot.Parent and selfRoot.Parent) then break end
			local toCaster = selfRoot.Position - oppRoot.Position
			local dist = toCaster.Magnitude
			if dist <= Magnetism.contactRadius then
				if ctx and ctx.dealDamage then
					ctx.dealDamage(opponent, Magnetism.pullDamage)
				end
				VFX.ring(oppRoot.Position, CHAIN_COLOR, 8, 0.45)
				hit = true
				break
			end
			-- Aim the velocity at the caster's CURRENT position, not the
			-- one captured at activate time. Slight upward bias keeps the
			-- target from grinding on the floor mid-pull.
			local dir = (dist > 0.01) and toCaster.Unit or Vector3.new(0, 0, -1)
			bv.Velocity = dir * Magnetism.pullSpeed + Vector3.new(0, 14, 0)
			-- Chain visual ~12fps so the chain segments overlap into a
			-- continuous "tether" look without being expensive.
			if os.clock() - lastChain > 0.08 then
				spawnChain(selfRoot.Position + Vector3.new(0, 1, 0),
					oppRoot.Position + Vector3.new(0, 1, 0))
				lastChain = os.clock()
			end
			task.wait(0.04)
		end
		if bv and bv.Parent then bv:Destroy() end

		-- Snap-to-range fallback. If the BV finished without making
		-- contact (blocked by geometry, opponent jumped over caster, etc.)
		-- pull them inside contactRadius and apply the damage anyway.
		-- Otherwise, Magnetism would feel like it just doesn't work.
		if not hit and oppRoot.Parent and selfRoot.Parent then
			local toCaster = selfRoot.Position - oppRoot.Position
			local dist = toCaster.Magnitude
			if dist > Magnetism.contactRadius and dist <= Magnetism.range + 10 then
				local dir = (dist > 0.01) and toCaster.Unit or Vector3.new(0, 0, -1)
				local landing = selfRoot.Position - dir * (Magnetism.contactRadius - 1)
				oppRoot.CFrame = CFrame.new(
					landing.X,
					oppRoot.Position.Y,
					landing.Z
				)
				if ctx and ctx.dealDamage then
					ctx.dealDamage(opponent, Magnetism.pullDamage)
				end
				VFX.ring(oppRoot.Position, CHAIN_COLOR, 8, 0.45)
				VFX.sphereBurst(oppRoot.Position + Vector3.new(0, 1, 0),
					CHAIN_COLOR, 5, 0.3)
			end
		end
	end)
end

return Magnetism
