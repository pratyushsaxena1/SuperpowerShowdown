-- Mirror: 2.5s window where damage taken is reflected back to the
-- attacker at 100%. Implemented entirely as a character attribute
-- (`Mirroring` + `MirrorEnds`) so CombatService.applyDamage can read it
-- in one place and redirect the damage. No per-frame work here — once
-- the attribute is set, the combat path does the rest.
--
-- Visual: a ForceField-material shield bubble around the player that
-- shimmers and a tighter pulsing ring at the player's feet. Both fade
-- out when the window ends. ForceField is the Roblox classic "shielded"
-- read so other players immediately understand they're attacking through
-- a reflect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local VFX = require(ReplicatedStorage.SharedModules.VFX)

local Mirror = {}

Mirror.cooldown = 9
Mirror.meleeDamage = 8
Mirror.speedMultiplier = 1.0
Mirror.duration = 2.5

local SHIELD_COLOR = Color3.fromRGB(160, 220, 255)
local FLASH_COLOR  = Color3.fromRGB(255, 255, 255)

function Mirror.onEquip() end
function Mirror.onUnequip(character)
	if not character then return end
	character:SetAttribute("Mirroring", false)
	character:SetAttribute("MirrorEnds", 0)
end

function Mirror.onActivate(character, _opponent, _ctx)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	character:SetAttribute("Mirroring", true)
	character:SetAttribute("MirrorEnds", os.clock() + Mirror.duration)

	-- Shield bubble: ForceField material at moderate transparency so the
	-- player's body still reads through it. Welded to HRP so it tracks
	-- movement without a per-frame loop.
	local shield = Instance.new("Part")
	shield.Name = "MirrorShield"
	shield.Shape = Enum.PartType.Ball
	shield.Anchored = false
	shield.CanCollide = false
	shield.CanQuery = false
	shield.CanTouch = false
	shield.Massless = true
	shield.Size = Vector3.new(7.5, 7.5, 7.5)
	shield.Material = Enum.Material.ForceField
	shield.Color = SHIELD_COLOR
	shield.Transparency = 1
	shield.CFrame = hrp.CFrame
	shield.Parent = hrp
	Debris:AddItem(shield, Mirror.duration + 0.4)

	local weld = Instance.new("Weld")
	weld.Part0 = hrp
	weld.Part1 = shield
	weld.C0 = CFrame.new(0, 0, 0)
	weld.Parent = shield

	-- Light source pulses with the shield.
	local light = Instance.new("PointLight")
	light.Color = SHIELD_COLOR
	light.Range = 12
	light.Brightness = 2.5
	light.Shadows = false
	light.Parent = shield
	Debris:AddItem(light, Mirror.duration + 0.4)

	TweenService:Create(shield, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Transparency = 0.4 }):Play()

	-- Pulse the brightness so the shield reads as "active" instead of
	-- being a static prop.
	task.spawn(function()
		while shield.Parent do
			local up = TweenService:Create(light, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { Brightness = 4 })
			up:Play(); up.Completed:Wait()
			if not shield.Parent then break end
			local dn = TweenService:Create(light, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { Brightness = 1.6 })
			dn:Play(); dn.Completed:Wait()
		end
	end)

	VFX.ring(hrp.Position, FLASH_COLOR, 8, 0.4)
	VFX.sphereBurst(hrp.Position + Vector3.new(0, 1, 0), SHIELD_COLOR, 6, 0.35)

	task.delay(Mirror.duration, function()
		if character and character.Parent then
			character:SetAttribute("Mirroring", false)
			character:SetAttribute("MirrorEnds", 0)
			local h = character:FindFirstChild("HumanoidRootPart")
			if h then
				VFX.sphereBurst(h.Position, SHIELD_COLOR, 5, 0.3)
				VFX.ring(h.Position, FLASH_COLOR, 6, 0.3)
			end
		end
		if shield and shield.Parent then
			TweenService:Create(shield, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
	end)
end

return Mirror
