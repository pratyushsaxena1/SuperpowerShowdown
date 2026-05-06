local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local VFX = {}

local effectBin
local function getBin()
	if effectBin and effectBin.Parent then return effectBin end
	effectBin = Workspace:FindFirstChild("_VFX")
	if not effectBin then
		effectBin = Instance.new("Folder")
		effectBin.Name = "_VFX"
		effectBin.Parent = Workspace
	end
	return effectBin
end

function VFX.sphereBurst(position, color, maxSize, duration)
	duration = duration or 0.4
	maxSize = maxSize or 8
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color or Color3.fromRGB(255, 200, 150)
	p.Size = Vector3.new(1, 1, 1)
	p.Position = position
	p.Transparency = 0.1
	p.Parent = getBin()
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(maxSize, maxSize, maxSize),
		Transparency = 1,
	}):Play()
	task.delay(duration + 0.1, function() if p.Parent then p:Destroy() end end)
end

function VFX.beam(startPos, endPos, color, thickness, duration)
	duration = duration or 0.25
	thickness = thickness or 0.5
	local dist = (endPos - startPos).Magnitude
	if dist < 0.1 then return end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = color or Color3.fromRGB(255, 80, 80)
	p.Size = Vector3.new(thickness, thickness, dist)
	p.CFrame = CFrame.new(startPos:Lerp(endPos, 0.5), endPos)
	p.Transparency = 0.05
	p.Parent = getBin()
	TweenService:Create(p, TweenInfo.new(duration), { Transparency = 1 }):Play()
	task.delay(duration + 0.1, function() if p.Parent then p:Destroy() end end)
end

function VFX.ring(position, color, maxRadius, duration)
	duration = duration or 0.5
	maxRadius = maxRadius or 12
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = color or Color3.fromRGB(255, 255, 255)
	p.Size = Vector3.new(0.4, 1, 1)
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	p.Transparency = 0.1
	p.Parent = getBin()
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, maxRadius * 2, maxRadius * 2),
		Transparency = 1,
	}):Play()
	task.delay(duration + 0.1, function() if p.Parent then p:Destroy() end end)
end

function VFX.sparkle(position, color, count, spread, duration)
	duration = duration or 0.6
	count = count or 8
	spread = spread or 4
	for i = 1, count do
		local p = Instance.new("Part")
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.Material = Enum.Material.Neon
		p.Color = color or Color3.fromRGB(120, 255, 180)
		p.Size = Vector3.new(0.4, 0.4, 0.4)
		p.Position = position + Vector3.new((math.random() - 0.5) * 2, (math.random() - 0.5) * 2, (math.random() - 0.5) * 2)
		p.Velocity = Vector3.new((math.random() - 0.5) * spread * 4, math.random() * spread * 3, (math.random() - 0.5) * spread * 4)
		p.Parent = getBin()
		TweenService:Create(p, TweenInfo.new(duration), { Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.1) }):Play()
		task.delay(duration + 0.1, function() if p.Parent then p:Destroy() end end)
	end
end

function VFX.characterFade(character, toTransparency, seconds)
	seconds = seconds or 0.1
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			TweenService:Create(part, TweenInfo.new(seconds), { Transparency = toTransparency }):Play()
		elseif part:IsA("Decal") then
			TweenService:Create(part, TweenInfo.new(seconds), { Transparency = toTransparency }):Play()
		end
	end
end

return VFX
