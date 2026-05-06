local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VFX = require(ReplicatedStorage.SharedModules.VFX)

local SuperStrength = {}

SuperStrength.cooldown = 3
SuperStrength.meleeDamage = 16
SuperStrength.knockback = 90
SuperStrength.speedMultiplier = 0.92
SuperStrength.slamDamage = 14
SuperStrength.throwDamage = 32
SuperStrength.pickupRange = 14
SuperStrength.crateHitRadius = 5.5
SuperStrength.trackDuration = 2.5

function SuperStrength.onEquip() end
function SuperStrength.onUnequip() end

local function findNearestHeavy(position)
	local best, bestDist = nil, math.huge
	for _, item in ipairs(CollectionService:GetTagged("HeavyItem")) do
		if item:IsA("BasePart") and item.Parent then
			local d = (item.Position - position).Magnitude
			if d < SuperStrength.pickupRange and d < bestDist then
				best, bestDist = item, d
			end
		end
	end
	return best
end

function SuperStrength.onActivate(character, opponent, ctx)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.01 then flat = flat.Unit else flat = Vector3.new(0, 0, 1) end

	-- Soft auto-aim: bias the throw direction toward the opponent's flat
	-- position so casual throws land. Skipped when the opponent is invisible
	-- so stealth still rewards them - falls back to the player's facing.
	local aimDir = flat
	local oRootForAim = opponent and opponent.Parent and opponent:FindFirstChild("HumanoidRootPart")
	if oRootForAim and not opponent:GetAttribute("IsInvisible") then
		local toOpp = oRootForAim.Position - root.Position
		local flatOpp = Vector3.new(toOpp.X, 0, toOpp.Z)
		if flatOpp.Magnitude > 0.01 then aimDir = flatOpp.Unit end
	end

	local heavy = findNearestHeavy(root.Position)
	if heavy then
		heavy.Anchored = false
		heavy.CanCollide = true
		heavy.CFrame = CFrame.new(root.Position + aimDir * 4 + Vector3.new(0, 3, 0))
		heavy.AssemblyLinearVelocity = aimDir * 140 + Vector3.new(0, 28, 0)
		VFX.sphereBurst(heavy.Position, Color3.fromRGB(255, 180, 120), 4, 0.3)

		local damaged = false
		local hitDecoys = {}
		-- Proximity-tracked damage: checks every frame for ~2.5s whether the thrown
		-- crate has reached the opponent (or any decoy) hitbox. More reliable than
		-- Touched alone, which can miss if the crate grazes a limb.
		task.spawn(function()
			local startT = os.clock()
			while os.clock() - startT < SuperStrength.trackDuration do
				if not heavy.Parent then break end
				local speed = heavy.AssemblyLinearVelocity.Magnitude
				if speed <= 10 then task.wait(0.03) continue end

				if not damaged and opponent and opponent.Parent then
					local oRoot = opponent:FindFirstChild("HumanoidRootPart")
					if oRoot and (heavy.Position - oRoot.Position).Magnitude < SuperStrength.crateHitRadius then
						damaged = true
						if ctx and ctx.dealDamage then
							ctx.dealDamage(opponent, SuperStrength.throwDamage)
						end
						VFX.sphereBurst(heavy.Position, Color3.fromRGB(255, 120, 80), 10, 0.45)
					end
				end

				for _, decoy in ipairs(CollectionService:GetTagged("Decoy")) do
					if decoy ~= character and decoy.Parent and not hitDecoys[decoy] then
						local dRoot = decoy:FindFirstChild("HumanoidRootPart")
						if dRoot and (heavy.Position - dRoot.Position).Magnitude < SuperStrength.crateHitRadius then
							hitDecoys[decoy] = true
							if ctx and ctx.dealDamage then
								ctx.dealDamage(decoy, SuperStrength.throwDamage)
							end
							VFX.sphereBurst(heavy.Position, Color3.fromRGB(255, 120, 80), 6, 0.3)
						end
					end
				end

				if damaged and #CollectionService:GetTagged("Decoy") == 0 then break end
				task.wait(0.03)
			end
		end)

		-- Also keep a Touched fallback for AoE feel (e.g., if the crate tumbles into them later)
		local touched = {}
		local conn
		conn = heavy.Touched:Connect(function(hit)
			local hitChar = hit:FindFirstAncestorOfClass("Model")
			if not hitChar or hitChar == character then return end
			if touched[hitChar] then return end
			local hum = hitChar:FindFirstChildOfClass("Humanoid")
			if not hum then return end
			touched[hitChar] = true
			if ctx and ctx.dealDamage then
				if hitChar == opponent and not damaged then
					damaged = true
					ctx.dealDamage(opponent, SuperStrength.throwDamage)
				elseif CollectionService:HasTag(hitChar, "Decoy") and not hitDecoys[hitChar] then
					hitDecoys[hitChar] = true
					ctx.dealDamage(hitChar, SuperStrength.throwDamage)
				end
			end
			VFX.sphereBurst(heavy.Position, Color3.fromRGB(255, 120, 80), 7, 0.35)
		end)
		task.delay(6, function() if conn then conn:Disconnect() end end)
		return
	end

	local slammed = false
	if opponent then
		local oRoot = opponent:FindFirstChild("HumanoidRootPart")
		if oRoot and (oRoot.Position - root.Position).Magnitude < 12 then
			local dir = (oRoot.Position - root.Position)
			if dir.Magnitude > 0.01 then dir = dir.Unit end
			oRoot.AssemblyLinearVelocity = oRoot.AssemblyLinearVelocity + (dir * SuperStrength.knockback + Vector3.new(0, 45, 0))
			if ctx and ctx.dealDamage then ctx.dealDamage(opponent, SuperStrength.slamDamage) end
			slammed = true
		end
	end

	for _, decoy in ipairs(CollectionService:GetTagged("Decoy")) do
		if decoy ~= character and decoy.Parent then
			local dRoot = decoy:FindFirstChild("HumanoidRootPart")
			if dRoot and (dRoot.Position - root.Position).Magnitude < 12 then
				local dir = (dRoot.Position - root.Position)
				if dir.Magnitude > 0.01 then dir = dir.Unit end
				dRoot.AssemblyLinearVelocity = dRoot.AssemblyLinearVelocity + (dir * SuperStrength.knockback + Vector3.new(0, 45, 0))
				if ctx and ctx.dealDamage then ctx.dealDamage(decoy, SuperStrength.slamDamage) end
				slammed = true
			end
		end
	end

	if slammed then
		VFX.ring(root.Position, Color3.fromRGB(255, 140, 80), 10, 0.4)
	end
end

return SuperStrength
