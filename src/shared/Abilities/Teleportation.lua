local Teleportation = {}
Teleportation.Name = "Teleportation"
Teleportation.DisplayName = "Blink"
Teleportation.Description = "Blink 30 studs forward. Press E to teleport."
Teleportation.Cooldown = 4
Teleportation.Color = Color3.fromRGB(200, 120, 255)
Teleportation.PunchDamageMultiplier = 1.0

function Teleportation.onMatchStart(_state) end

function Teleportation.activate(state)
	local char = state.character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local fromPos = root.Position
	local forward = root.CFrame.LookVector
	local target = fromPos + forward * 30 + Vector3.new(0, 2, 0)
	root.CFrame = CFrame.new(target, target + forward)
	state.broadcastEffect("blink", { from = fromPos, to = target })
end

function Teleportation.cleanup(_state) end

return Teleportation
