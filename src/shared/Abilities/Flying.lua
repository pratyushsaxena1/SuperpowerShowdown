local Flying = {}
Flying.Name = "Flying"
Flying.DisplayName = "Aerial Ace"
Flying.Description = "Soar above the arena. Press E to burst upward."
Flying.Cooldown = 0.6
Flying.Color = Color3.fromRGB(120, 200, 255)
Flying.PunchDamageMultiplier = 1.0

function Flying.onMatchStart(state)
	local char = state.character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local bv = Instance.new("BodyVelocity")
	bv.Name = "FlyingBV"
	bv.MaxForce = Vector3.new(0, math.huge, 0)
	bv.Velocity = Vector3.new(0, 0, 0)
	bv.Parent = root
	state.bv = bv
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.JumpHeight = 0 end
end

function Flying.activate(state)
	if not state.bv or not state.bv.Parent then return end
	state.bv.Velocity = Vector3.new(0, 60, 0)
	-- Visual lift puff at the player's feet.
	local char = state.character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		state.broadcastEffect("flap", { pos = root.Position })
	end
	task.delay(0.4, function()
		if state.bv and state.bv.Parent then
			state.bv.Velocity = Vector3.new(0, 0, 0)
		end
	end)
end

function Flying.cleanup(state)
	if state.bv then state.bv:Destroy() state.bv = nil end
end

return Flying
