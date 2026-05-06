local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local VFX = require(ReplicatedStorage.SharedModules.VFX)

local LightningStrike = {}

LightningStrike.cooldown = 8
LightningStrike.meleeDamage = 8
LightningStrike.speedMultiplier = 1.0
LightningStrike.strikeRadius = 7
LightningStrike.warnDuration = 0.55
LightningStrike.damage = 30
LightningStrike.boltHeight = 80

local function getBin()
	local bin = Workspace:FindFirstChild("_VFX")
	if not bin then
		bin = Instance.new("Folder")
		bin.Name = "_VFX"
		bin.Parent = Workspace
	end
	return bin
end

local function spawnWarningZone(position)
	-- Ground marker (thin cylinder) + slowly-expanding ring to telegraph the hit.
	local marker = Instance.new("Part")
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.Shape = Enum.PartType.Cylinder
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 230, 120)
	marker.Size = Vector3.new(0.2, LightningStrike.strikeRadius * 2, LightningStrike.strikeRadius * 2)
	marker.CFrame = CFrame.new(position - Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	marker.Transparency = 0.45
	marker.Parent = getBin()

	TweenService:Create(marker, TweenInfo.new(LightningStrike.warnDuration), {
		Transparency = 0.15,
	}):Play()
	return marker
end

function LightningStrike.onEquip() end
function LightningStrike.onUnequip() end

function LightningStrike.onActivate(character, opponent, ctx)
	if not (opponent and opponent.Parent) then return end
	-- Can't auto-aim at an invisible target. Strike simply fizzles.
	if opponent:GetAttribute("IsInvisible") then return end
	local oRoot = opponent:FindFirstChild("HumanoidRootPart")
	if not oRoot then return end

	local targetPos = oRoot.Position
	local marker = spawnWarningZone(targetPos)

	task.delay(LightningStrike.warnDuration, function()
		if marker and marker.Parent then marker:Destroy() end

		local strikeTop = targetPos + Vector3.new(0, LightningStrike.boltHeight, 0)
		VFX.beam(strikeTop, targetPos, Color3.fromRGB(200, 220, 255), 1.8, 0.35)
		VFX.beam(strikeTop, targetPos, Color3.fromRGB(255, 255, 255), 0.6, 0.2)
		VFX.sphereBurst(targetPos, Color3.fromRGB(220, 240, 255), 10, 0.45)
		VFX.sparkle(targetPos + Vector3.new(0, 2, 0), Color3.fromRGB(220, 240, 255), 24, 6, 0.55)

		if opponent and opponent.Parent then
			local current = opponent:FindFirstChild("HumanoidRootPart")
			if current and (current.Position - targetPos).Magnitude <= LightningStrike.strikeRadius then
				if ctx and ctx.dealDamage then
					ctx.dealDamage(opponent, LightningStrike.damage)
				end
				current.AssemblyLinearVelocity =
					current.AssemblyLinearVelocity + Vector3.new(0, 35, 0)
			end
		end

		-- Decoys caught in the strike zone also take the hit.
		for _, decoy in ipairs(CollectionService:GetTagged("Decoy")) do
			if decoy ~= character and decoy.Parent then
				local dRoot = decoy:FindFirstChild("HumanoidRootPart")
				if dRoot and (dRoot.Position - targetPos).Magnitude <= LightningStrike.strikeRadius then
					if ctx and ctx.dealDamage then
						ctx.dealDamage(decoy, LightningStrike.damage)
					end
					dRoot.AssemblyLinearVelocity =
						dRoot.AssemblyLinearVelocity + Vector3.new(0, 35, 0)
				end
			end
		end
	end)
end

return LightningStrike
