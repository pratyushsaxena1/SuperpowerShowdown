local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VFX = require(ReplicatedStorage.SharedModules.VFX)

local Shockwave = {}

Shockwave.cooldown = 6
Shockwave.meleeDamage = 8
Shockwave.speedMultiplier = 1.0
Shockwave.radius = 36
Shockwave.damage = 28
Shockwave.knockback = 100
Shockwave.crateImpulse = 150

function Shockwave.onEquip() end
function Shockwave.onUnequip() end

local function hasLineOfSight(fromPos, toPart, character, targetModel)
	-- Raycast from center outward; if anything solid that isn't the attacker,
	-- the target, or VFX is in the way, the target is considered blocked.
	local dir = toPart.Position - fromPos
	local dist = dir.Magnitude
	if dist < 0.1 then return true end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.IgnoreWater = true
	rp.FilterDescendantsInstances = {
		character,
		targetModel,
		Workspace:FindFirstChild("_VFX"),
	}
	local hit = Workspace:Raycast(fromPos, dir, rp)
	return hit == nil
end

function Shockwave.onActivate(character, opponent, ctx)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local center = root.Position

	-- Visuals: big expanding ring + sphere burst
	VFX.ring(center, Color3.fromRGB(255, 220, 100), Shockwave.radius, 0.55)
	VFX.sphereBurst(center, Color3.fromRGB(255, 180, 80), Shockwave.radius * 1.2, 0.4)
	VFX.sparkle(center + Vector3.new(0, 2, 0), Color3.fromRGB(255, 220, 120), 18, 4, 0.6)

	-- Damage opponent if they're within radius AND line-of-sight is clear.
	-- Standing behind a HeavyCrate / Cover / Wall blocks the hit.
	if opponent and opponent.Parent then
		local oRoot = opponent:FindFirstChild("HumanoidRootPart")
		if oRoot then
			local offset = oRoot.Position - center
			local dist = offset.Magnitude
			if dist <= Shockwave.radius then
				if hasLineOfSight(center, oRoot, character, opponent) then
					if ctx and ctx.dealDamage then
						ctx.dealDamage(opponent, Shockwave.damage)
					end
					-- Knockback in radial direction
					local dir = Vector3.new(offset.X, 0, offset.Z)
					if dir.Magnitude > 0.01 then dir = dir.Unit else dir = root.CFrame.LookVector end
					oRoot.AssemblyLinearVelocity =
						oRoot.AssemblyLinearVelocity + dir * Shockwave.knockback + Vector3.new(0, 30, 0)
				end
			end
		end
	end

	-- Decoys (Duplication clones) live as direct workspace children and
	-- are tagged "Decoy" by the Duplication ability. Iterate the tag set
	-- directly so the LOS raycast doesn't get blocked by the opponent's
	-- own body parts standing between caster and a decoy spawned right
	-- behind them — a shockwave is AoE, decoys should be wiped regardless
	-- of cover. They're MaxHealth = 1, so any TakeDamage kills them.
	for _, decoy in ipairs(CollectionService:GetTagged("Decoy")) do
		if decoy ~= character and decoy ~= opponent and decoy.Parent then
			local hum = decoy:FindFirstChildOfClass("Humanoid")
			local hRoot = decoy:FindFirstChild("HumanoidRootPart")
			if hum and hRoot and hum.Health > 0 then
				if (hRoot.Position - center).Magnitude <= Shockwave.radius then
					hum:TakeDamage(math.max(1, hum.MaxHealth))
				end
			end
		end
	end

	-- Push unanchored heavy crates away from the impact point
	for _, item in ipairs(CollectionService:GetTagged("HeavyItem")) do
		if item:IsA("BasePart") and item.Parent and not item.Anchored then
			local offset = item.Position - center
			local dist = offset.Magnitude
			if dist <= Shockwave.radius and dist > 0.1 then
				local dir = Vector3.new(offset.X, 0, offset.Z)
				if dir.Magnitude > 0.01 then
					dir = dir.Unit
					local falloff = 1 - (dist / Shockwave.radius)
					item.AssemblyLinearVelocity =
						item.AssemblyLinearVelocity + dir * Shockwave.crateImpulse * falloff
							+ Vector3.new(0, 20 * falloff, 0)
				end
			end
		end
	end
end

return Shockwave
