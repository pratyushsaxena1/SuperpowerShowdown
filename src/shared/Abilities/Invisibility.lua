local Invisibility = {}
Invisibility.Name = "Invisibility"
Invisibility.DisplayName = "Invisibility"
Invisibility.Description = "Vanish for 4 seconds. Press E to disappear (you can still attack)."
Invisibility.Cooldown = 10
Invisibility.Color = Color3.fromRGB(180, 180, 200)
Invisibility.PunchDamageMultiplier = 1.5

local function setTransparency(char, t)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = t
			d.Transparency = math.max(d.Transparency, t)
		elseif d:IsA("Decal") then
			d.Transparency = t
		end
	end
end

function Invisibility.onMatchStart(_state) end

function Invisibility.activate(state)
	local char = state.character
	if not char then return end
	setTransparency(char, 0.95)
	task.delay(4, function()
		if state.character == char and char.Parent then
			setTransparency(char, 0)
		end
	end)
end

function Invisibility.cleanup(state)
	local char = state.character
	if char then setTransparency(char, 0) end
end

return Invisibility
