local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VFX = require(ReplicatedStorage.SharedModules.VFX)

local Duplication = {}

Duplication.cooldown = 4
Duplication.meleeDamage = 8
Duplication.speedMultiplier = 1.0
Duplication.decoyDuration = 9
Duplication.decoyCount = 4
Duplication.spawnRadius = 6

-- Default Roblox R15 animation assets. The Animate LocalScript bundled with
-- CreateHumanoidModelFromDescription() won't run in a Workspace model, so we
-- load these directly onto each decoy's Animator and toggle via Humanoid.Running.
-- The previous IDs (913401643, 913376220) are no longer hosted and spammed
-- "Animation failed to load" warnings every spawn. These are the current
-- public R15 walk/idle anims.
local ANIM_IDS = {
	idle = "rbxassetid://180435571",
	run  = "rbxassetid://180426354",
}

local function buildDecoyFromPlayer(sourceCharacter)
	local sourceHum = sourceCharacter:FindFirstChildOfClass("Humanoid")
	if sourceHum then
		local ok, desc = pcall(function() return sourceHum:GetAppliedDescription() end)
		if ok and desc then
			local ok2, model = pcall(function()
				return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
			end)
			if ok2 and model then return model end
		end
	end
	sourceCharacter.Archivable = true
	for _, d in ipairs(sourceCharacter:GetDescendants()) do
		pcall(function() d.Archivable = true end)
	end
	local ok, clone = pcall(function() return sourceCharacter:Clone() end)
	if ok then return clone end
	return nil
end

local function stripDecoy(decoy)
	for _, d in ipairs(decoy:GetChildren()) do
		if d:IsA("ForceField") then d:Destroy() end
		if d.Name == "Animate" and (d:IsA("LocalScript") or d:IsA("Script")) then d:Destroy() end
	end
	for _, d in ipairs(decoy:GetDescendants()) do
		if d:IsA("BillboardGui") then d:Destroy() end
	end
end

local function configureDecoy(decoy)
	local hum = decoy:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.MaxHealth = 1
		hum.Health = 1
		hum.WalkSpeed = 16
		hum.JumpPower = 50
		hum.AutoRotate = true
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.NameDisplayDistance = 0
		hum.BreakJointsOnDeath = true
	end
	if not decoy.PrimaryPart then
		decoy.PrimaryPart = decoy:FindFirstChild("HumanoidRootPart")
	end
end

local function attachDefaultAnimations(decoy)
	local hum = decoy:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)

	local function load(id, priority)
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function() return animator:LoadAnimation(a) end)
		if not ok or not track then return nil end
		track.Priority = priority
		track.Looped = true
		return track
	end

	local idle = load(ANIM_IDS.idle, Enum.AnimationPriority.Idle)
	local run = load(ANIM_IDS.run, Enum.AnimationPriority.Movement)

	if idle then idle:Play(0) end

	-- Humanoid.Running fires whenever the running speed transitions. When the
	-- decoy is moving toward the opponent, speed > 0 → run. When it stops
	-- (arrived, or :MoveTo finishes), speed == 0 → run fades and idle shows.
	-- Much more reliable than polling MoveDirection.
	if run then
		hum.Running:Connect(function(speed)
			if speed > 0.1 then
				if not run.IsPlaying then run:Play(0.15) end
			else
				if run.IsPlaying then run:Stop(0.15) end
			end
		end)
	end
end

function Duplication.onEquip() end
function Duplication.onUnequip() end

function Duplication.onActivate(character, opponent, ctx)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	VFX.sphereBurst(root.Position, Color3.fromRGB(140, 220, 255), 9, 0.4)
	VFX.ring(root.Position, Color3.fromRGB(140, 220, 255), 11, 0.5)

	for i = 1, Duplication.decoyCount do
		local decoy = buildDecoyFromPlayer(character)
		if not decoy then continue end

		decoy.Name = "Decoy_" .. i
		stripDecoy(decoy)
		configureDecoy(decoy)

		local angle = (i - 1) * (2 * math.pi / Duplication.decoyCount) + math.random() * 0.35
		local offset = Vector3.new(
			math.cos(angle) * Duplication.spawnRadius, 0,
			math.sin(angle) * Duplication.spawnRadius
		)
		decoy:PivotTo(character:GetPivot() + offset + Vector3.new(0, 0.5, 0))
		decoy.Parent = Workspace
		-- Tagged so CombatService.onAttack can target decoys with punches.
		CollectionService:AddTag(decoy, "Decoy")
		attachDefaultAnimations(decoy)

		-- Same brain as the AI opponent in BotAIController: every 0.3s, if
		-- the opponent is far, :MoveTo their position (humanoid pathfinds
		-- around simple obstacles on its own) and randomly jump at close
		-- range to hop over cover. Decoys deal no damage and die in one hit
		-- (MaxHealth = 1 + BreakJointsOnDeath).
		local decoyHum = decoy:FindFirstChildOfClass("Humanoid")
		local decoyRoot = decoy:FindFirstChild("HumanoidRootPart")
		if decoyHum and decoyRoot then
			task.spawn(function()
				local startT = os.clock()
				local lastJump = 0

				while decoy.Parent and decoyHum.Health > 0
					and (os.clock() - startT) < Duplication.decoyDuration do
					-- If the opponent is invisible, decoys must not be able
					-- to track them. Stand idle and skip the chase tick.
					local opponentInvisible = opponent
						and opponent:GetAttribute("IsInvisible") == true
					local oRoot = opponent and opponent.Parent
						and not opponentInvisible
						and opponent:FindFirstChild("HumanoidRootPart")
					local targetPos
					if oRoot then
						targetPos = oRoot.Position
					elseif opponentInvisible then
						-- Halt in place while the target is cloaked.
						decoyHum:Move(Vector3.new(0, 0, 0), false)
						task.wait(0.2)
						continue
					elseif root.Parent then
						targetPos = root.Position
					else
						break
					end

					local dist = (decoyRoot.Position - targetPos).Magnitude
					local now = os.clock()

					if dist > 6 then
						decoyHum:MoveTo(targetPos)
						if dist < 12 and now - lastJump > 2 and math.random() < 0.25 then
							lastJump = now
							decoyHum.Jump = true
						end
					else
						-- Stop cleanly; MoveTo(self) caused start-stop jitter.
						decoyHum:Move(Vector3.new(0, 0, 0), false)
						local flat = Vector3.new(targetPos.X - decoyRoot.Position.X, 0, targetPos.Z - decoyRoot.Position.Z)
						if flat.Magnitude > 0.05 then
							decoyRoot.CFrame = CFrame.lookAt(decoyRoot.Position, decoyRoot.Position + flat.Unit)
						end
					end

					task.wait(0.2)
				end

				if decoy.Parent then
					local pos = (decoy.PrimaryPart and decoy.PrimaryPart.Position) or root.Position
					VFX.sphereBurst(pos, Color3.fromRGB(140, 220, 255), 5, 0.3)
					decoy:Destroy()
				end
			end)

			decoyHum.Died:Connect(function()
				local pos = (decoy.PrimaryPart and decoy.PrimaryPart.Position) or root.Position
				VFX.sphereBurst(pos, Color3.fromRGB(180, 230, 255), 6, 0.3)
				task.delay(0.2, function() if decoy.Parent then decoy:Destroy() end end)
			end)
		end
	end
end

return Duplication
