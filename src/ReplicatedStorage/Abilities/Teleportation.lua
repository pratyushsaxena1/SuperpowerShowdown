local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VFX = require(ReplicatedStorage.SharedModules.VFX)

local Teleportation = {}

Teleportation.cooldown = 2.5
Teleportation.meleeDamage = 9
Teleportation.speedMultiplier = 1.0
Teleportation.blinkDistance = 64

-- Inner-arena half-extents. These match the values Flying uses in
-- ClientController (the playable area inside the arena walls). Using the
-- full arena bounding box would include the thick walls, so the previous
-- clamp let blinks land between the wall faces — i.e. "outside the
-- building". minY is set above the floor so feet don't sink into marble.
Teleportation.innerHalfX = 100
Teleportation.innerHalfZ = 100
Teleportation.innerMaxY = 80
Teleportation.innerMinY = 4
Teleportation.boundsBuffer = 4

function Teleportation.onEquip() end
function Teleportation.onUnequip() end

function Teleportation.onActivate(character, _opponent, ctx)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local hum = character:FindFirstChildOfClass("Humanoid")
	local onGround = hum and hum.FloorMaterial ~= Enum.Material.Air

	local dir
	if ctx and ctx.aimDir and ctx.aimDir.Magnitude > 0.01 then
		dir = ctx.aimDir.Unit
	else
		local look = root.CFrame.LookVector
		dir = (look.Magnitude > 0.01) and look.Unit or Vector3.new(0, 0, -1)
	end

	-- If standing on ground and aiming level or below horizon, flatten to
	-- pure horizontal so the blink always travels its full distance instead
	-- of clipping into the floor. Upward aim is preserved for stairs.
	if onGround and dir.Y < 0.2 then
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.01 then dir = flat.Unit end
	end

	local startPos = root.Position
	local endPos = startPos + dir * Teleportation.blinkDistance

	-- Clamp to the arena's inner playable area so the player can't blink
	-- past a wall. ArenaCenter is set by ArenaManager / AIMatchCoordinator
	-- when the match starts; in the lobby it's nil and clamping is skipped
	-- (full blink distance allowed in lobby).
	local arenaCenter = character:GetAttribute("ArenaCenter")
	if typeof(arenaCenter) == "Vector3" then
		local buf = Teleportation.boundsBuffer
		local hx = Teleportation.innerHalfX - buf
		local hz = Teleportation.innerHalfZ - buf
		local minY = arenaCenter.Y + Teleportation.innerMinY
		local maxY = arenaCenter.Y + Teleportation.innerMaxY - buf
		endPos = Vector3.new(
			math.clamp(endPos.X, arenaCenter.X - hx, arenaCenter.X + hx),
			math.clamp(endPos.Y, minY, maxY),
			math.clamp(endPos.Z, arenaCenter.Z - hz, arenaCenter.Z + hz)
		)
	end

	-- Phase through obstacles: skip obstruction raycast. But don't end up
	-- stuck inside a part - if we'd land inside solid geometry, scan down
	-- to find a valid floor and put the player on top of it.
	local filter = { character }
	local vfx = Workspace:FindFirstChild("_VFX")
	if vfx then table.insert(filter, vfx) end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = filter

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = filter
	rp.IgnoreWater = true

	local stuck = #Workspace:GetPartBoundsInBox(
		CFrame.new(endPos), Vector3.new(3, 5, 3), overlapParams) > 0
	if stuck then
		local scanTop = endPos + Vector3.new(0, 80, 0)
		local floor = Workspace:Raycast(scanTop, Vector3.new(0, -200, 0), rp)
		if floor then
			endPos = floor.Position + Vector3.new(0, 3, 0)
		else
			endPos = endPos + Vector3.new(0, 8, 0)
		end
	end

	-- Keep facing flat on the XZ plane so the camera doesn't flip when
	-- teleporting at a steep vertical angle.
	local facingFlat = Vector3.new(dir.X, 0, dir.Z)
	if facingFlat.Magnitude < 0.01 then
		facingFlat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if facingFlat.Magnitude < 0.01 then facingFlat = Vector3.new(0, 0, -1) end
	facingFlat = facingFlat.Unit

	VFX.sphereBurst(startPos, Color3.fromRGB(200, 120, 255), 6, 0.35)
	VFX.ring(startPos, Color3.fromRGB(200, 120, 255), 8, 0.4)
	VFX.characterFade(character, 0.9, 0.05)

	task.wait(0.06)
	root.CFrame = CFrame.new(endPos, endPos + facingFlat)

	VFX.characterFade(character, 0, 0.1)
	VFX.sphereBurst(endPos, Color3.fromRGB(200, 120, 255), 6, 0.35)
	VFX.ring(endPos, Color3.fromRGB(200, 120, 255), 8, 0.4)
end

return Teleportation
