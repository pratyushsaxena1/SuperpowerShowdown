-- Magnetism: yank the opponent's body toward you with a magnetic chain,
-- then deal a one-shot damage hit on contact. Strong "anti-cover" tool —
-- pulls a hiding opponent out from behind a crate. Doesn't override their
-- input on the way in (they keep WASD control), it just adds a strong pull
-- vector via a temp BodyVelocity.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local VFX = require(ReplicatedStorage.SharedModules.VFX)

local Magnetism = {}

Magnetism.cooldown = 6
Magnetism.meleeDamage = 8
Magnetism.speedMultiplier = 1.0
Magnetism.pullDuration = 0.5
Magnetism.pullDamage = 14
-- Slightly larger contact radius than the previous 5 — a 5-stud check at
-- the END of the pull missed too often when the opponent stopped 5.5 studs
-- away (e.g. blocked by geometry on the way in). 7 is roughly punch range.
Magnetism.contactRadius = 7
Magnetism.range = 60

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
	local toOpp = oppRoot.Position - selfRoot.Position
	if toOpp.Magnitude > Magnetism.range then return end

	-- Visual chain. Swap the part out as the opponent moves so the chain
	-- always points at the right spot. Cheap because it's just a tween-out
	-- on a single part each tick.
	local startTime = os.clock()
	task.spawn(function()
		while os.clock() - startTime < Magnetism.pullDuration do
			if not (oppRoot.Parent and selfRoot.Parent) then return end
			spawnChain(selfRoot.Position + Vector3.new(0, 1, 0),
				oppRoot.Position + Vector3.new(0, 1, 0))
			task.wait(0.08)
		end
	end)

	-- Pull vector: enough to drag them in over pullDuration. Cancel out
	-- gravity with a small upward bias so the part doesn't grind on the
	-- floor and stall the pull.
	local pullVec = (selfRoot.Position - oppRoot.Position).Unit * 90
		+ Vector3.new(0, 18, 0)
	local bv = Instance.new("BodyVelocity")
	bv.Name = "MagnetismPull"
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Velocity = pullVec
	bv.Parent = oppRoot
	Debris:AddItem(bv, Magnetism.pullDuration)

	VFX.sphereBurst(selfRoot.Position + Vector3.new(0, 1, 0), CHAIN_COLOR, 6, 0.4)

	-- Sweep contact damage across the entire pull. As soon as the opponent
	-- enters contact range, deal the hit and stop checking. Old version
	-- only checked at pull end, which missed if the opponent slid past
	-- the caster mid-pull, or got blocked by geometry just shy of contact.
	task.spawn(function()
		local hit = false
		local checkUntil = os.clock() + Magnetism.pullDuration + 0.15
		while not hit and os.clock() < checkUntil do
			if not (opponent.Parent and selfRoot.Parent) then return end
			local dist = (oppRoot.Position - selfRoot.Position).Magnitude
			if dist <= Magnetism.contactRadius then
				if ctx and ctx.dealDamage then
					ctx.dealDamage(opponent, Magnetism.pullDamage)
				end
				VFX.ring(oppRoot.Position, CHAIN_COLOR, 8, 0.45)
				hit = true
			end
			task.wait(0.05)
		end
	end)
end

return Magnetism
